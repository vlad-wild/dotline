# shellcheck shell=bash
# Shared helpers for install.sh, update.sh and uninstall.sh.
#
# Every change to the system goes through these functions, so --dry-run shows
# it instead of doing it, and the manifest records it for uninstall.sh.

set -Eeuo pipefail

RICE_NAME="dotline"
RICE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$RICE_NAME"
MANIFEST="$STATE_DIR/manifest.json"
LOG_DIR="$STATE_DIR/log"
# shellcheck disable=SC2034  # used by install.sh
BACKUP_DIR="$STATE_DIR/backup/$(date +%Y%m%d-%H%M%S)"
BAK_SUFFIX=".$RICE_NAME.bak"

DRY_RUN=0
ASSUME_YES=0
declare -a OPTIONS=()

# ---------- output ----------

if [[ -t 1 ]]; then
    C_DIM=$'\e[2m' C_RED=$'\e[31m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
    C_DIM="" C_RED="" C_BOLD="" C_RESET=""
fi

LOG_FILE=""
_log() { [[ -n "$LOG_FILE" ]] && printf '%s %s\n' "$(date +%T)" "$*" >>"$LOG_FILE"; return 0; }
step() { printf '\n%s● %s%s\n' "$C_BOLD" "$*" "$C_RESET"; _log "STEP $*"; }
info() { printf '  %s\n' "$*"; _log "INFO $*"; }
note() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; _log "NOTE $*"; }
warn() { printf '  %s! %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; _log "WARN $*"; }
die() { printf '%s✘ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; _log "FAIL $*"; exit 1; }

trap 'die "Ошибка в строке $LINENO: $BASH_COMMAND"' ERR

start_log() {
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/$1-$(date +%Y%m%d-%H%M%S).log"
    _log "START $1 $*"
    note "Лог: $LOG_FILE"
}

# ---------- arguments ----------

# Parse the flags common to all scripts; the rest go to OPTIONS.
parse_common_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            -y | --yes) ASSUME_YES=1 ;;
            *) OPTIONS+=("$arg") ;;
        esac
    done
    if ((DRY_RUN)); then
        note "Режим --dry-run: ничего не меняется, только показываю план."
    fi
}

has_option() {
    local want="$1" o
    for o in "${OPTIONS[@]}"; do [[ "$o" == "$want" ]] && return 0; done
    return 1
}

# ---------- running things ----------

# Run a command, or print it in --dry-run.
run() {
    if ((DRY_RUN)); then
        printf '  %s$ %s%s\n' "$C_DIM" "$*" "$C_RESET"
        return 0
    fi
    _log "RUN $*"
    "$@"
}

sudo_run() { run sudo "$@"; }

confirm() {
    local prompt="$1" answer
    if ((ASSUME_YES)); then return 0; fi
    if ((DRY_RUN)); then
        note "(спросил бы: $prompt)"
        return 0
    fi
    read -r -p "  $prompt [y/N] " answer
    [[ "$answer" =~ ^[yYдД]$ ]]
}

# ---------- preflight ----------

require_not_root() {
    [[ $EUID -ne 0 ]] || die "Запускайте от своего пользователя, не от root: sudo вызывается там, где нужно."
}

require_arch() {
    [[ -f /etc/arch-release ]] || die "Это не Arch Linux."
}

require_sudo() {
    command -v sudo >/dev/null || die "Нет sudo."
    ((DRY_RUN)) && return 0
    sudo -v || die "sudo недоступен для $USER."
}

require_network() {
    ((DRY_RUN)) && return 0
    curl -fsS --max-time 8 -o /dev/null https://archlinux.org ||
        die "Нет интернета (archlinux.org недоступен)."
}

# ---------- manifest ----------
# JSON with everything this rice changed, so uninstall.sh can undo exactly that.

manifest_init() {
    mkdir -p "$STATE_DIR"
    if [[ ! -f "$MANIFEST" ]]; then
        ((DRY_RUN)) && return 0
        jq -n --arg v "$(rice_version)" --arg d "$(date -Iseconds)" \
            '{version:$v, installed:$d, packages:[], files:[], services:[], groups:[], notes:{}}' \
            >"$MANIFEST"
    fi
}

# manifest_append <array> <json-object>
manifest_append() {
    ((DRY_RUN)) && return 0
    local tmp
    tmp="$(mktemp)"
    jq --arg k "$1" --argjson v "$2" '.[$k] += [$v] | .[$k] |= unique' "$MANIFEST" >"$tmp"
    mv "$tmp" "$MANIFEST"
}

# manifest_set_note <key> <string value>
manifest_set_note() {
    ((DRY_RUN)) && return 0
    local tmp
    tmp="$(mktemp)"
    jq --arg k "$1" --arg v "$2" '.notes[$k] = $v' "$MANIFEST" >"$tmp"
    mv "$tmp" "$MANIFEST"
}

manifest_get() {
    [[ -f "$MANIFEST" ]] || return 0
    jq -r "$1" "$MANIFEST"
}

rice_version() {
    git -C "$RICE_ROOT" describe --always --dirty 2>/dev/null || echo "unknown"
}

# ---------- snapshots ----------

snapshot() {
    if command -v snapper >/dev/null && sudo snapper -c root list >/dev/null 2>&1; then
        sudo_run snapper -c root create --cleanup-algorithm number --description "$RICE_NAME: $1"
        info "Снапшот snapper: $1"
    else
        note "snapper не настроен — снапшот пропущен."
    fi
}

# ---------- packages ----------

pkg_installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# Package names from packages/<group>.txt (comments and blank lines skipped).
read_packages() {
    local file="$RICE_ROOT/packages/$1.txt"
    [[ -f "$file" ]] || die "Нет списка пакетов $file"
    sed -e 's/#.*//' -e 's/[[:space:]]\+$//' -e '/^[[:space:]]*$/d' "$file"
}

enable_multilib() {
    grep -q '^\[multilib\]' /etc/pacman.conf && return 0
    step "Включаю репозиторий multilib (нужен для Steam и 32-битных драйверов)"
    local tmp
    tmp="$(mktemp)"
    sed '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf >"$tmp"
    install_system_file "$tmp" /etc/pacman.conf 0644
    sudo_run pacman -Sy
}

ensure_paru() {
    # `command -v paru` only checks that *some* file is on PATH, not that
    # it actually runs — a stale paru-bin left over from before this was
    # switched to a source build (see below) still "exists" while
    # crashing on startup (cannot open shared object file: libalpm.soN).
    # `paru --version` catches that: it fails the same way the real
    # command would, so a broken binary correctly falls through to the
    # reinstall below instead of being silently accepted.
    command -v paru >/dev/null && paru --version >/dev/null 2>&1 && return 0
    step "Ставлю paru (AUR-помощник)"
    sudo_run pacman -S --needed --noconfirm base-devel git
    local dir
    dir="$(mktemp -d)"
    # Built from source (not paru-bin): a prebuilt binary is linked
    # against whatever libalpm.so the AUR maintainer's machine had at
    # build time — on a fresh pacstrap with a different Arch snapshot
    # that can mismatch the real libalpm here and crash paru outright
    # ("cannot open shared object file: libalpm.soN") before it even
    # gets to run. Building from source links against the libalpm
    # actually installed on this machine, so it can't go stale this way.
    run git clone --depth 1 https://aur.archlinux.org/paru.git "$dir/paru"
    if ((DRY_RUN)); then
        run makepkg -si --noconfirm
    else
        (cd "$dir/paru" && makepkg -si --noconfirm)
    fi
    manifest_append packages '"paru"'
}

# Names (of those given) that exist in the AUR, from its RPC API.
aur_existing() {
    local query="" p
    for p in "$@"; do query+="&arg[]=$p"; done
    curl -fsS --max-time 20 "https://aur.archlinux.org/rpc/v5/info?${query#&}" | jq -r '.results[].Name' || true
}

# Install packages that are not installed yet and remember which ones we added.
# Unknown names are reported and skipped instead of failing the whole run.
install_packages() {
    local -a want=() repo=() aur=() missing=()
    local p
    for p in "$@"; do pkg_installed "$p" || want+=("$p"); done
    ((${#want[@]})) || { note "Все пакеты уже установлены."; return 0; }

    for p in "${want[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1; then repo+=("$p"); else aur+=("$p"); fi
    done
    if ((${#aur[@]})); then
        local -a found=() in_aur=()
        mapfile -t found < <(aur_existing "${aur[@]}")
        for p in "${aur[@]}"; do
            if printf '%s\n' "${found[@]}" | grep -qx -- "$p"; then in_aur+=("$p"); else missing+=("$p"); fi
        done
        aur=("${in_aur[@]}")
    fi
    ((${#missing[@]})) && warn "Не найдены ни в репозиториях, ни в AUR (пропускаю): ${missing[*]}"

    ((${#repo[@]})) && info "Из репозиториев: ${repo[*]}"
    ((${#aur[@]})) && info "Из AUR: ${aur[*]}"
    ((${#repo[@]})) && sudo_run pacman -S --needed --noconfirm "${repo[@]}"
    ((${#aur[@]})) && run paru -S --needed --noconfirm "${aur[@]}"

    for p in "${repo[@]}" "${aur[@]}"; do
        if ((DRY_RUN)) || pkg_installed "$p"; then manifest_append packages "\"$p\""; fi
    done
}

# ---------- files ----------

# Install a file into the system: show the diff, ask, back up the original once
# (<path>.dotline.bak) and record it in the manifest.
install_system_file() {
    local src="$1" dest="$2" mode="${3:-0644}"
    [[ -f "$src" ]] || die "Нет файла $src"
    if [[ -f "$dest" ]] && sudo cmp -s "$src" "$dest"; then
        note "$dest уже актуален."
        return 0
    fi
    info "Файл $dest:"
    if [[ -f "$dest" ]]; then
        sudo diff -u "$dest" "$src" | sed 's/^/    /' || true
    else
        note "    (новый файл)"
    fi
    confirm "Записать $dest?" || { warn "Пропущено: $dest"; return 0; }

    local backup=""
    if [[ -e "$dest" && ! -e "$dest$BAK_SUFFIX" ]]; then
        backup="$dest$BAK_SUFFIX"
        sudo_run cp -a "$dest" "$backup"
    elif [[ -e "$dest$BAK_SUFFIX" ]]; then
        backup="$dest$BAK_SUFFIX"
    fi
    sudo_run install -Dm"$mode" "$src" "$dest"
    manifest_append files "$(jq -nc --arg p "$dest" --arg b "$backup" '{path:$p, backup:$b}')"
}

# Insert a line into an existing PAM service file, just before its first
# line starting with <group> (default "auth"). For a file we don't fully
# own (e.g. /etc/pam.d/sudo ships with the `sudo` package and carries its
# own account/password/session lines) — install_system_file's whole-file
# replace would be wrong here, so this edits in place instead. Idempotent:
# does nothing if the exact line is already present anywhere in the file.
# Caller is responsible for require_root_tty first.
pam_insert_line() {
    local dest="$1" line="$2" group="${3:-auth}"
    [[ -f "$dest" ]] || die "Нет файла $dest — это не тот PAM-сервис?"
    if grep -qxF "$line" "$dest"; then
        note "$dest уже содержит нужную строку."
        return 0
    fi
    local preview
    preview="$(awk -v l="$line" -v g="^$group" '!done && $0 ~ g {print l; done=1} {print}' "$dest")"
    info "В $dest добавляется первой строкой группы $group:"
    diff -u "$dest" <(printf '%s\n' "$preview") | sed 's/^/    /' || true
    confirm "Применить?" || { warn "Пропущено: $dest"; return 0; }

    local backup="$dest$BAK_SUFFIX"
    [[ -e "$backup" ]] || sudo_run cp -a "$dest" "$backup"
    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "$preview" >"$tmp"
    sudo_run cp "$tmp" "$dest"
    rm -f "$tmp"
    manifest_append files "$(jq -nc --arg p "$dest" --arg b "$backup" '{path:$p, backup:$b}')"
}

# /etc/pam.d/sudo ships with the `sudo` package and carries its own
# account/password/session lines — install_system_file's whole-file
# replace (used for polkit-1/greetd/qs-lock, which we fully own) would be
# wrong here, so this edits the one line in instead. Shared by install.sh
# and update.sh (idempotent, like pam_insert_line itself).
faceauth_pam_sudo() {
    has_option --skip-faceauth && return 0
    [[ -f /etc/pam.d/sudo ]] || { note "Нет /etc/pam.d/sudo (sudo не установлен?) — пропускаю."; return 0; }
    step "faceauth: строка в /etc/pam.d/sudo"
    require_root_tty
    pam_insert_line /etc/pam.d/sudo \
        "auth  sufficient  pam_exec.so quiet /usr/bin/faceauth-auth" auth
}

# PAM mistakes can lock you out: insist on an open root shell first.
require_root_tty() {
    ((DRY_RUN)) && return 0
    if who | awk '$1 == "root"' | grep -q .; then
        note "Открытая сессия root найдена — можно менять PAM."
        return 0
    fi
    warn "Перед изменением PAM откройте запасной вход: Ctrl+Alt+F3 → войдите как root → вернитесь сюда (Ctrl+Alt+F1/F2)."
    confirm "Сессия root открыта?" || die "Изменение PAM отменено."
}

# ---------- services ----------

# enable_service <system|user> <unit>
enable_service() {
    local scope="$1" unit="$2" was
    local -a sc=(systemctl)
    [[ "$scope" == user ]] && sc=(systemctl --user)
    if ! "${sc[@]}" list-unit-files "$unit" 2>/dev/null | grep -q "^$unit"; then
        warn "Службы $unit нет в системе — пропускаю."
        return 0
    fi
    was="$("${sc[@]}" is-enabled "$unit" 2>/dev/null || true)"
    if [[ "$was" == enabled ]]; then
        note "$unit уже включён."
        return 0
    fi
    if [[ "$scope" == system ]]; then sudo_run systemctl enable --now "$unit"; else run systemctl --user enable --now "$unit"; fi
    manifest_append services "$(jq -nc --arg s "$scope" --arg u "$unit" --arg w "${was:-unknown}" '{scope:$s, unit:$u, was:$w}')"
}

# ---------- groups ----------

# ---------- generated user files ----------

# Write content to a plain file under $HOME (not a stow package, not
# root-owned) and record it so uninstall.sh removes exactly this file.
write_user_file() {
    local dest="$1" content="$2"
    if ((DRY_RUN)); then
        note "(запись $dest)"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    printf '%s\n' "$content" >"$dest"
    manifest_append files "$(jq -nc --arg p "$dest" '{path:$p, backup:"", kind:"generated"}')"
}

# ---------- exposed commands ----------

# Expose scripts/<name> as a plain command ~/.local/bin/dotline-<name>, so
# niri keybindings and the settings window can spawn it by name instead of
# embedding this checkout's path. Called by install.sh and update.sh's
# relink(). Needs ~/.local/bin on PATH before niri starts — provided by
# dotfiles/environment/.config/environment.d/10-local-bin.conf (systemd
# --user, applies even though greetd never runs a login shell).
link_bin() {
    step "Команды (~/.local/bin)"
    run mkdir -p "$HOME/.local/bin"
    local script name link
    for script in "$@"; do
        name="$RICE_NAME-$script"
        link="$HOME/.local/bin/$name"
        if [[ -L "$link" && "$(readlink -f "$link")" == "$RICE_ROOT/scripts/$script" ]]; then
            note "$name уже указывает сюда."
            continue
        fi
        if [[ -e "$link" && ! -L "$link" ]]; then
            warn "$link уже существует и это не наша ссылка — пропускаю."
            continue
        fi
        run ln -sf "$RICE_ROOT/scripts/$script" "$link"
        manifest_append files "$(jq -nc --arg p "$link" '{path:$p, backup:"", kind:"symlink"}')"
    done
    local shown=() s
    for s in "$@"; do shown+=("$RICE_NAME-$s"); done
    info "Готово: ${shown[*]} → ~/.local/bin"
}

add_to_group() {
    local group="$1"
    id -nG "$USER" | tr ' ' '\n' | grep -qx "$group" && return 0
    getent group "$group" >/dev/null || { warn "Группы $group нет — пропускаю."; return 0; }
    sudo_run usermod -aG "$group" "$USER"
    manifest_append groups "\"$group\""
    note "Добавлен в группу $group (вступит в силу после перезахода)."
}
