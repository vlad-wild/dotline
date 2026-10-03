# shellcheck shell=bash
# Shared tail of scripts/wallpaper and scripts/theme: run palette-post,
# publish the result for the greeter, and nudge running apps to pick it up.
#
# Sourced after lib/common.sh (needs run/note/info/warn/RICE_ROOT/STATE_DIR).
# Deliberately never calls confirm(): both callers can run unattended from a
# keybinding, with no terminal to answer a prompt on.

PALETTE_WALLPAPER_FILE="$STATE_DIR/wallpaper"
PALETTE_MODE_FILE="$STATE_DIR/theme"
PALETTE_JSON="$STATE_DIR/palette.json"
PALETTE_GREETER_JSON="/var/lib/dotline/palette.json"
# Empty/absent = wallpaper-derived palette is active (the default); set to
# a name from palette-post's PALETTE_PRESETS when a ready-made theme
# (plan's "готовая палитра") is active instead. "oled" is independent of
# either — plain "on"/absent, applies to whichever source is active.
PALETTE_PRESET_FILE="$STATE_DIR/preset"
PALETTE_OLED_FILE="$STATE_DIR/oled"

palette_saved_mode() {
    [[ -f "$PALETTE_MODE_FILE" ]] && cat "$PALETTE_MODE_FILE" || echo auto
}

palette_saved_wallpaper() {
    # The trailing `|| true` matters, not just style: under `set -e`, a bare
    # `x="$(palette_saved_wallpaper)"` at the call site would otherwise abort
    # the whole script the first time this file doesn't exist yet (e.g. before
    # any wallpaper has ever been set) — a plain assignment statement isn't
    # one of the contexts `set -e` exempts, unlike `foo && bar` used as its
    # own statement. Caught by actually running this on a fresh state dir,
    # not just reasoned about.
    [[ -f "$PALETTE_WALLPAPER_FILE" ]] && cat "$PALETTE_WALLPAPER_FILE"
    return 0
}

palette_saved_preset() {
    [[ -f "$PALETTE_PRESET_FILE" ]] && cat "$PALETTE_PRESET_FILE"
    return 0
}

palette_oled_enabled() {
    [[ -f "$PALETTE_OLED_FILE" ]] && [[ "$(cat "$PALETTE_OLED_FILE")" == "on" ]]
}

# Shared by palette_apply/palette_apply_preset: runs palette-post with
# whatever args the caller built, reads the output back (DRY_RUN just logs
# the args and returns, same early-exit shape both callers need), and does
# the two things that don't depend on wallpaper-vs-preset at all.
#
# Prints the indented log to stderr (so it's still visible to the user
# immediately, even though the caller wraps this in `out="$(...)"`, which
# only captures stdout) and returns the raw output on stdout, for
# _palette_finish's mode= parsing below.
_palette_run() {
    mkdir -p "$STATE_DIR"
    if ((DRY_RUN)); then
        note "(palette-post $*)"
        return 0
    fi
    local out
    if ! out="$("$RICE_ROOT/scripts/palette-post" "$@" --state-dir "$STATE_DIR" 2>&1)"; then
        warn "palette-post не справился:"
        printf '%s\n' "$out" | sed 's/^/    /' >&2
        return 1
    fi
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    printf '%s\n' "$out"
}

# palette_apply <image> <mode: auto|dark|light>
# Runs palette-post from a wallpaper, remembers the choice, and reloads
# consumers. Clears any active preset — wallpaper and preset are mutually
# exclusive sources for the same palette.json.
palette_apply() {
    local image="$1" mode="$2" out
    local -a args=("$image" --mode "$mode")
    palette_oled_enabled && args+=(--oled)
    out="$(_palette_run "${args[@]}")" || return 1
    ((DRY_RUN)) && return 0

    printf '%s' "$image" >"$PALETTE_WALLPAPER_FILE"
    printf '%s' "$mode" >"$PALETTE_MODE_FILE"
    rm -f "$PALETTE_PRESET_FILE"

    _palette_finish "$out" "$mode"
}

# palette_apply_preset <name> <mode: dark|light>
# Same as palette_apply, but from a ready-made palette (plan's "готовая
# палитра") instead of a wallpaper — see palette-post --preset.
palette_apply_preset() {
    local name="$1" mode="$2" out
    local -a args=(--preset "$name" --mode "$mode")
    palette_oled_enabled && args+=(--oled)
    out="$(_palette_run "${args[@]}")" || return 1
    ((DRY_RUN)) && return 0

    printf '%s' "$name" >"$PALETTE_PRESET_FILE"
    printf '%s' "$mode" >"$PALETTE_MODE_FILE"

    _palette_finish "$out" "$mode"
}

# palette_set_oled <on|off>
# Independent of wallpaper/preset — re-applies whichever is currently
# active with the new --oled state, so it takes effect immediately rather
# than waiting for the next wallpaper/theme change.
palette_set_oled() {
    local state="$1"
    printf '%s' "$state" >"$PALETTE_OLED_FILE"
    local preset mode
    preset="$(palette_saved_preset)"
    mode="$(palette_saved_mode)"
    if [[ -n "$preset" ]]; then
        palette_apply_preset "$preset" "$mode"
    else
        local image
        image="$(palette_saved_wallpaper)"
        [[ -n "$image" ]] && palette_apply "$image" "$mode"
    fi
}

_palette_finish() {
    local out="$1" mode="$2"
    # palette-post already resolved auto -> dark/light and printed which one
    # it picked in its first output line ("mode=dark ..."); read it back
    # instead of re-guessing, so gsettings matches what the palette actually is.
    local resolved
    resolved="$(printf '%s\n' "$out" | sed -n 's/^mode=\(dark\|light\).*/\1/p' | head -1)"
    [[ -n "$resolved" ]] || resolved="$mode"

    _palette_publish_for_greeter
    _palette_reload_apps "$resolved"
}

# Best-effort copy for greetd's session (root-owned path): skipped quietly
# without cached sudo credentials, since the greeter falls back to its last
# known palette and this is not worth an interactive password prompt from
# a keybinding-triggered script.
_palette_publish_for_greeter() {
    if sudo -n true 2>/dev/null; then
        if sudo -n install -Dm644 "$PALETTE_JSON" "$PALETTE_GREETER_JSON" 2>/dev/null; then
            info "Обновлена палитра для greetd."
        else
            note "Не удалось обновить палитру greetd (нет прав) — попробуйте ./update.sh."
        fi
    else
        note "Нет сохранённого sudo — палитра greetd не обновлена сейчас (обновится через ./update.sh)."
    fi
}

_palette_reload_apps() {
    local resolved="$1"
    # kitty: theme-dotline.conf changed on disk, ask running instances to
    # re-read their config (this is what kitty's own docs recommend for a
    # live theme reload, instead of restarting the terminal).
    if command -v kitty >/dev/null && pgrep -x kitty >/dev/null; then
        kitty @ set-colors --all --configured "$HOME/.config/kitty/theme-dotline.conf" 2>/dev/null ||
            pkill -SIGUSR1 kitty 2>/dev/null || true
    fi
    # niri: colors.kdl changed; ask the running compositor to reload.
    if command -v niri >/dev/null && pgrep -x niri >/dev/null; then
        niri msg action load-config-file 2>/dev/null ||
            warn "niri не принял новый конфиг — проверьте: niri validate -c ~/.config/niri/config.kdl"
    fi
    # Our own gtk.css handles accent/surface tokens, but most GTK4/libadwaita
    # apps decide light vs dark from this gsettings key, not from gtk.css.
    if command -v gsettings >/dev/null; then
        gsettings set org.gnome.desktop.interface color-scheme "prefer-$resolved" 2>/dev/null || true
    fi
    # fuzzel re-reads its ini on every launch: no signal needed.
}
