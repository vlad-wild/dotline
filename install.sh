#!/usr/bin/env bash
# Install the dotline desktop on a fresh Arch Linux (see docs/install-arch.md).
#
#   ./install.sh [--dry-run] [--yes] [--with-egpu] [--with-rocm] [--with-calendar]
#                [--skip-apps] [--skip-faceauth] [--faceauth-src=PATH|URL]
#                [--groups=base,desktop,…]
#
# Everything it adds is recorded in ~/.local/state/dotline/manifest.json,
# so ./uninstall.sh can put the system back.

source "$(dirname "$0")/lib/common.sh"

MATRIX_SANS_VERSION="1.722"
MATRIX_SANS_SHA256="0b864d016e15155779fb524472d39c14e22ab396d43bc2bf09fd1d4dbadf1dee"
FACEAUTH_REPO="https://github.com/vlad-wild/faceauth"

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

option_value() {
    local name="$1" o
    for o in "${OPTIONS[@]}"; do
        [[ "$o" == "$name="* ]] && { printf '%s' "${o#*=}"; return 0; }
    done
    return 1
}

# ---------- steps ----------

bootstrap() {
    step "Подготовка"
    require_arch
    require_not_root
    require_sudo
    require_network
    command -v jq >/dev/null || sudo_run pacman -S --needed --noconfirm jq
    manifest_init
    manifest_set_note installed_from "$(rice_version)"
    snapshot "до install.sh"
    # Picked up by systemd --user before niri starts (see config.kdl's
    # startup line, which falls back to this if no wallpaper was set yet).
    write_user_file "$HOME/.config/environment.d/20-dotline-root.conf" \
        "DOTLINE_ROOT=$RICE_ROOT"
}

packages() {
    local -a groups=(base desktop laptop network gaming)
    has_option --skip-apps || groups+=(apps)
    local only
    if only="$(option_value --groups)"; then
        IFS=, read -r -a groups <<<"$only"
    fi
    if has_option --with-egpu; then
        groups+=(egpu)
    fi
    has_option --with-rocm && groups+=(rocm)
    has_option --with-calendar && groups+=(calendar)
    # lib32-gamemode/lib32-vulkan-intel (gaming, installed by default) and
    # the AMD lib32-* packages (egpu) all need multilib — enable it
    # whenever either group is actually in play, not only for --with-egpu.
    if [[ " ${groups[*]} " == *" gaming "* || " ${groups[*]} " == *" egpu "* ]]; then
        enable_multilib
    fi

    ensure_paru
    local g
    for g in "${groups[@]}"; do
        step "Пакеты: $g"
        local -a list=()
        mapfile -t list < <(read_packages "$g")
        install_packages "${list[@]}"
    done
}

# Matrix Sans Print: the dot-matrix font with Cyrillic (not packaged in Arch).
fonts() {
    step "Шрифт Matrix Sans $MATRIX_SANS_VERSION"
    local dest="$HOME/.local/share/fonts/$RICE_NAME"
    if [[ -f "$dest/MatrixSansPrint-Regular.ttf" ]]; then
        note "Уже установлен."
        return 0
    fi
    local tmp zip
    tmp="$(mktemp -d)"
    zip="$tmp/matrix-sans.zip"
    run curl -fsSL -o "$zip" \
        "https://github.com/FriedOrange/MatrixSans/releases/download/v$MATRIX_SANS_VERSION/MatrixSans-v$MATRIX_SANS_VERSION.zip"
    if ((!DRY_RUN)); then
        echo "$MATRIX_SANS_SHA256  $zip" | sha256sum -c --quiet || die "Контрольная сумма Matrix Sans не совпала."
    fi
    run mkdir -p "$dest"
    run bsdtar -xf "$zip" -C "$dest" --strip-components 3 '*/fonts/ttf/*.ttf'
    run bsdtar -xf "$zip" -C "$dest" --strip-components 1 '*/OFL.txt'
    run fc-cache -f "$dest"
    manifest_append files "$(jq -nc --arg p "$dest" '{path:$p, backup:"", kind:"user-dir"}')"
}

# Build faceauth as a pacman package: from a local checkout (any branch) or the GitHub repo.
faceauth() {
    has_option --skip-faceauth && return 0
    step "faceauth (вход по лицу)"
    local src
    src="$(option_value --faceauth-src || echo "${FACEAUTH_SRC:-$FACEAUTH_REPO}")"
    local build
    build="$(mktemp -d)"
    if [[ -d "$src/.git" ]]; then
        local commit
        commit="$(git -C "$src" rev-parse HEAD)"
        info "Собираю из локального репозитория $src ($commit)"
        run cp "$src/PKGBUILD" "$src/faceauth.install" "$build/"
        run sed -i "s|^source=.*|source=(\"faceauth::git+file://$src#commit=$commit\")|" "$build/PKGBUILD"
        manifest_set_note faceauth_commit "$commit"
    else
        info "Собираю из $src"
        run git clone --depth 1 "$src" "$build/src"
        run cp "$build/src/PKGBUILD" "$build/src/faceauth.install" "$build/"
    fi
    (cd "$build" && run makepkg -si --noconfirm --needed)
    manifest_append packages '"faceauth"'
    enable_service system faceauthd.socket
}

# Link dotfiles/<package> into $HOME with GNU stow; conflicting files are moved
# to the backup directory first.
dotfiles() {
    step "Конфиги (dotfiles)"
    local dir pkg
    shopt -s nullglob
    local -a pkgs=()
    for dir in "$RICE_ROOT"/dotfiles/*/; do pkgs+=("$(basename "$dir")"); done
    shopt -u nullglob
    ((${#pkgs[@]})) || { note "Пакетов dotfiles пока нет."; return 0; }

    for pkg in "${pkgs[@]}"; do
        local -a conflicts=()
        mapfile -t conflicts < <(
            stow --no-folding -n -d "$RICE_ROOT/dotfiles" -t "$HOME" "$pkg" 2>&1 |
                sed -n 's/.*existing target \(is not owned by stow\|is neither a link nor a directory\): \(.*\)$/\2/p; s/.*over existing target \(.*\) since.*/\1/p'
        )
        local c
        for c in "${conflicts[@]}"; do
            [[ -n "$c" ]] || continue
            run mkdir -p "$BACKUP_DIR/$(dirname "$c")"
            run mv "$HOME/$c" "$BACKUP_DIR/$c"
            note "Сохранил ваш $c → $BACKUP_DIR/$c"
        done
        run stow --no-folding -d "$RICE_ROOT/dotfiles" -t "$HOME" "$pkg"
        manifest_append files "$(jq -nc --arg p "$pkg" --arg b "$BACKUP_DIR" '{path:$p, backup:$b, kind:"stow"}')"
    done
    info "Связано: ${pkgs[*]}"
}

# Copy system/<path> to /<path>; PAM files only with a root shell open.
system_files() {
    step "Системные файлы"
    local -a files=()
    mapfile -t files < <(cd "$RICE_ROOT/system" 2>/dev/null && find . -type f ! -name '.gitkeep' | sed 's|^\./||' | sort)
    ((${#files[@]})) || { note "Системных файлов пока нет."; return 0; }
    local f mode pam_checked=0
    for f in "${files[@]}"; do
        if [[ "$f" == etc/pam.d/* && $pam_checked -eq 0 ]]; then
            require_root_tty
            pam_checked=1
        fi
        # systemd's system-sleep hooks must be executable, or they're
        # silently never run (confirmed from systemd-sleep(8)) — every
        # other system/ file is a passive config, 0644 everywhere else.
        mode=0644
        [[ "$f" == usr/lib/systemd/system-sleep/* ]] && mode=0755
        install_system_file "$RICE_ROOT/system/$f" "/$f" "$mode"
    done
}

services() {
    step "Службы"
    # Picks up any new unit file system_files() just dropped in
    # /usr/lib/systemd/system (dotline-battery-limit.service isn't from a
    # package, so systemd has no other way to notice it exists yet).
    sudo_run systemctl daemon-reload
    enable_service system NetworkManager.service
    enable_service system bluetooth.service
    enable_service system power-profiles-daemon.service
    enable_service system dotline-battery-limit.service
    enable_service system dotline-fwupd-refresh.timer
    has_option --with-egpu && enable_service system switcheroo-control.service
    # greetd replaces the current display manager once its config is part of system/.
    if [[ -f "$RICE_ROOT/system/etc/greetd/config.toml" ]]; then
        local current
        current="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || true)"
        if [[ -n "$current" && "$current" != greetd.service ]]; then
            manifest_set_note display_manager_before "$current"
            sudo_run systemctl disable "$current"
        fi
        enable_service system greetd.service
    fi
}

groups() {
    step "Группы"
    add_to_group video   # camera for `faceauth capture` and camera effects
    add_to_group render  # NPU / GPU compute
    add_to_group i2c     # ddcutil (external monitor brightness)
}

# KDE Connect (see docs/phone.md): TCP for pairing/plugins, UDP for discovery.
firewall() {
    pkg_installed kdeconnect || return 0
    if command -v ufw >/dev/null && sudo ufw status 2>/dev/null | grep -q "^Status: active"; then
        step "Фаервол (ufw): открываю 1714:1764/tcp,udp для KDE Connect"
        sudo_run ufw allow 1714:1764/tcp
        sudo_run ufw allow 1714:1764/udp
        manifest_set_note firewall_kdeconnect ufw
    elif command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
        step "Фаервол (firewalld): открываю 1714-1764/tcp,udp для KDE Connect"
        sudo_run firewall-cmd --permanent --add-port=1714-1764/tcp
        sudo_run firewall-cmd --permanent --add-port=1714-1764/udp
        sudo_run firewall-cmd --reload
        manifest_set_note firewall_kdeconnect firewalld
    fi
}

finish() {
    step "Готово"
    info "Дальше:"
    info "  1. Перезагрузка (или выход и вход), чтобы применились группы и службы."
    has_option --skip-faceauth || info "  2. Запись лица: sudo faceauth add -u $USER   (или страница «Лицо» в настройках)"
    info "  3. Перенос данных из Windows: MIGRATION.md"
    note "Удалить всё, что поставил этот скрипт: ./uninstall.sh --dry-run, затем ./uninstall.sh"
}

main() {
    parse_common_args "$@"
    has_option --help && usage
    start_log install
    if has_option --only-faceauth; then
        require_not_root
        require_sudo
        manifest_init
        faceauth
        return 0
    fi
    bootstrap
    packages
    fonts
    faceauth
    faceauth_pam_sudo
    dotfiles
    link_bin wallpaper theme osd power phone menu battery migrate capture debug doctor app webapp
    system_files
    services
    groups
    firewall
    finish
}

main "$@"
