#!/usr/bin/env bash
# Update the system and the dotline desktop.
#
#   ./update.sh [--dry-run] [--yes] [--no-system] [--firmware]
#
# 1. pulls this repository (fast-forward only), 2. snapshot + full system
# upgrade, 3. installs packages newly added to packages/*.txt and offers to
# remove ones dropped from the lists (only if the rice installed them),
# 4. rebuilds faceauth when its source moved on, 5. re-links dotfiles and
# re-copies changed system files, 6. runs pending migrations/, 7. checks configs.

source "$(dirname "$0")/lib/common.sh"

MIGRATION_STATE="$STATE_DIR/migration"

pull_repo() {
    step "Репозиторий рис"
    if [[ -n "$(git -C "$RICE_ROOT" status --porcelain)" ]]; then
        warn "Есть локальные изменения — обновление репозитория пропущено:"
        git -C "$RICE_ROOT" status --short | sed 's/^/    /'
        return 0
    fi
    if ! git -C "$RICE_ROOT" remote get-url origin >/dev/null 2>&1; then
        note "У репозитория нет origin — пропускаю git pull."
        return 0
    fi
    local before
    before="$(git -C "$RICE_ROOT" rev-parse HEAD)"
    run git -C "$RICE_ROOT" pull --ff-only
    if [[ "$before" != "$(git -C "$RICE_ROOT" rev-parse HEAD)" ]]; then
        info "Изменения:"
        git -C "$RICE_ROOT" log --oneline "$before..HEAD" | sed 's/^/    /'
        # The new version of this script may differ: run it again.
        ((DRY_RUN)) || exec "$0" "$@" --no-pull
    fi
}

system_upgrade() {
    has_option --no-system && return 0
    step "Обновление системы"
    snapshot "до update.sh"
    run paru -Syu --noconfirm
}

firmware() {
    has_option --firmware || { note "Прошивки: ./update.sh --firmware (только от сети)."; return 0; }
    step "Прошивки (fwupd)"
    if [[ "$(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1)" != 1 ]]; then
        warn "Ноутбук не на зарядке — прошивки не обновляю."
        return 0
    fi
    run fwupdmgr refresh --force
    run fwupdmgr get-updates || true
    if confirm "Установить обновления прошивок?"; then run fwupdmgr update; fi
}

sync_packages() {
    step "Списки пакетов"
    local -a groups=(base desktop laptop network gaming)
    [[ -f "$RICE_ROOT/packages/apps.txt" ]] && manifest_get '.packages[]' | grep -qxf <(read_packages apps) && groups+=(apps)
    # vulkan-radeon (not steam — that moved to packages/gaming.txt, which
    # installs by default regardless of the eGPU) is egpu-specific.
    manifest_get '.packages[]' | grep -qx vulkan-radeon && groups+=(egpu)
    manifest_get '.packages[]' | grep -qx rocminfo && groups+=(rocm)
    # lib32-gamemode/lib32-vulkan-intel (gaming, always wanted) and the
    # AMD lib32-* packages (egpu) need multilib.
    if [[ " ${groups[*]} " == *" gaming "* || " ${groups[*]} " == *" egpu "* ]]; then
        enable_multilib
    fi

    local -a wanted=() g
    for g in "${groups[@]}"; do mapfile -t -O "${#wanted[@]}" wanted < <(read_packages "$g"); done
    install_packages "${wanted[@]}"

    # Installed by the rice earlier, no longer in any list.
    local -a dropped=()
    local p
    while read -r p; do
        [[ -z "$p" || "$p" == paru-bin || "$p" == faceauth ]] && continue
        printf '%s\n' "${wanted[@]}" | grep -qx "$p" || dropped+=("$p")
    done < <(manifest_get '.packages[]')
    if ((${#dropped[@]})); then
        info "Больше не входят в рис: ${dropped[*]}"
        if confirm "Удалить их?"; then
            sudo_run pacman -Rns --noconfirm "${dropped[@]}" || warn "Часть пакетов не удалена (нужны другим)."
            ((DRY_RUN)) || {
                local tmp
                tmp="$(mktemp)"
                jq --argjson d "$(printf '%s\n' "${dropped[@]}" | jq -R . | jq -s .)" '.packages -= $d' "$MANIFEST" >"$tmp" && mv "$tmp" "$MANIFEST"
            }
        fi
    fi
}

faceauth_rebuild() {
    local recorded src
    recorded="$(manifest_get '.notes.faceauth_commit // empty')"
    [[ -n "$recorded" ]] || return 0
    src="${FACEAUTH_SRC:-$HOME/dev/faceauth}"
    [[ -d "$src/.git" ]] || return 0
    local head
    head="$(git -C "$src" rev-parse HEAD)"
    [[ "$head" == "$recorded" ]] && return 0
    step "faceauth: новая версия в $src"
    local -a args=(--only-faceauth --faceauth-src="$src" --yes)
    ((DRY_RUN)) && args+=(--dry-run)
    "$RICE_ROOT/install.sh" "${args[@]}" || warn "Не удалось пересобрать faceauth."
}

relink() {
    step "Конфиги и системные файлы"
    local dir
    shopt -s nullglob
    for dir in "$RICE_ROOT"/dotfiles/*/; do
        run stow --no-folding --restow -d "$RICE_ROOT/dotfiles" -t "$HOME" "$(basename "$dir")"
    done
    shopt -u nullglob
    link_bin wallpaper theme osd power phone menu battery migrate capture debug doctor app webapp
    local -a files=()
    mapfile -t files < <(cd "$RICE_ROOT/system" 2>/dev/null && find . -type f ! -name '.gitkeep' | sed 's|^\./||' | sort)
    local f mode
    for f in "${files[@]}"; do
        [[ -f "/$f" ]] && sudo cmp -s "$RICE_ROOT/system/$f" "/$f" && continue
        [[ "$f" == etc/pam.d/* ]] && require_root_tty
        mode=0644
        [[ "$f" == usr/lib/systemd/system-sleep/* ]] && mode=0755
        install_system_file "$RICE_ROOT/system/$f" "/$f" "$mode"
    done
    # In case a unit file's content changed (new/renamed unit files are
    # rare after the first install, but a changed one needs this to
    # actually take effect on the next `systemctl restart`).
    sudo_run systemctl daemon-reload
}

# migrations/NNNN-name.sh run once each, in order; they must be idempotent.
migrations() {
    local done_n=0 m n
    [[ -f "$MIGRATION_STATE" ]] && done_n="$(cat "$MIGRATION_STATE")"
    shopt -s nullglob
    for m in "$RICE_ROOT"/migrations/[0-9][0-9][0-9][0-9]-*.sh; do
        n="$(basename "$m" | cut -c1-4)"
        ((10#$n > 10#$done_n)) || continue
        step "Миграция $(basename "$m")"
        run bash "$m"
        ((DRY_RUN)) || echo "$n" >"$MIGRATION_STATE"
    done
    shopt -u nullglob
}

check_configs() {
    step "Проверка конфигов"
    if command -v niri >/dev/null && [[ -f "$HOME/.config/niri/config.kdl" ]]; then
        niri validate -c "$HOME/.config/niri/config.kdl" && info "niri: конфиг в порядке" ||
            warn "niri: ошибка в конфиге — откатите изменения dotfiles (git -C $RICE_ROOT log)."
    fi
    if command -v faceauth >/dev/null; then
        sudo faceauth doctor | tail -n 5 | sed 's/^/    /' || true
    fi
}

main() {
    parse_common_args "$@"
    require_not_root
    require_sudo
    start_log update
    manifest_init
    has_option --no-pull || pull_repo "$@"
    system_upgrade
    firmware
    sync_packages
    faceauth_rebuild
    faceauth_pam_sudo
    relink
    migrations
    check_configs
    step "Обновление завершено"
}

main "$@"
