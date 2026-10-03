#!/usr/bin/env bash
# Undo what install.sh / update.sh changed, using the manifest.
#
#   ./uninstall.sh [--dry-run] [--yes] [--purge-packages] [--remove-faceauth] [--keep-state]
#
# By default packages stay installed (other things may use them); pass
# --purge-packages to remove exactly the ones the rice added. Face models in
# /var/lib/faceauth are only deleted after a separate question.

source "$(dirname "$0")/lib/common.sh"

show_plan() {
    step "Что будет возвращено"
    [[ -f "$MANIFEST" ]] || die "Манифест не найден ($MANIFEST): рис не устанавливался этим скриптом."
    info "Системные файлы: $(manifest_get '[.files[] | select(.kind == null)] | length')"
    info "Ссылки dotfiles: $(manifest_get '[.files[] | select(.kind == "stow")] | map(.path) | join(", ")')"
    info "Службы: $(manifest_get '.services | map(.unit) | join(", ")')"
    info "Группы: $(manifest_get '.groups | join(", ")')"
    local dm
    dm="$(manifest_get '.notes.display_manager_before // empty')"
    [[ -n "$dm" ]] && info "Вернуть менеджер входа: $dm"
    if has_option --purge-packages; then
        info "Пакеты к удалению: $(manifest_get '.packages | join(" ")')"
    else
        note "Пакеты остаются (удалить: --purge-packages)."
    fi
    confirm "Продолжить?" || die "Отменено."
}

restore_system_files() {
    step "Системные файлы"
    local -a entries=()
    # PAM first, with a root shell open, so a mistake cannot lock you out.
    mapfile -t entries < <(manifest_get '[.files[] | select(.kind == null)] | sort_by(.path | startswith("/etc/pam.d/") | not) | .[] | [.path, .backup] | @tsv')
    local line path backup pam_checked=0
    for line in "${entries[@]}"; do
        IFS=$'\t' read -r path backup <<<"$line"
        if [[ "$path" == /etc/pam.d/* && $pam_checked -eq 0 ]]; then
            require_root_tty
            pam_checked=1
        fi
        if [[ -n "$backup" && -e "$backup" ]]; then
            sudo_run mv -f "$backup" "$path"
            info "Восстановлен $path"
        else
            sudo_run rm -f "$path"
            info "Удалён $path (его не было до установки)"
        fi
    done
    sudo_run systemctl daemon-reload
}

restore_services() {
    step "Службы"
    local line scope unit was
    while IFS=$'\t' read -r scope unit was; do
        [[ -n "$unit" ]] || continue
        [[ "$was" == enabled ]] && continue
        if [[ "$scope" == user ]]; then run systemctl --user disable --now "$unit"; else sudo_run systemctl disable --now "$unit"; fi
        info "Выключена $unit"
    done < <(manifest_get '.services[] | [.scope, .unit, .was] | @tsv')
    local dm
    dm="$(manifest_get '.notes.display_manager_before // empty')"
    if [[ -n "$dm" ]]; then
        sudo_run systemctl enable "$dm"
        info "Менеджер входа снова $dm"
    fi
}

unlink_dotfiles() {
    step "Конфиги"
    local pkg backup
    while IFS=$'\t' read -r pkg backup; do
        [[ -n "$pkg" ]] || continue
        [[ -d "$RICE_ROOT/dotfiles/$pkg" ]] && run stow --no-folding -D -d "$RICE_ROOT/dotfiles" -t "$HOME" "$pkg"
        if [[ -d "$backup" ]]; then
            # Put back the user's own files that install.sh moved aside.
            run cp -an "$backup/." "$HOME/"
        fi
    done < <(manifest_get '.files[] | select(.kind == "stow") | [.path, .backup] | @tsv')
    local dir
    while read -r dir; do
        [[ -n "$dir" ]] && run rm -rf "$dir" && info "Удалено $dir"
    done < <(manifest_get '.files[] | select(.kind == "user-dir") | .path')
    run fc-cache -f >/dev/null

    local link
    while read -r link; do
        [[ -n "$link" && -L "$link" ]] && run rm -f "$link" && info "Убрана ссылка $link"
    done < <(manifest_get '.files[] | select(.kind == "symlink") | .path')

    local gen
    while read -r gen; do
        [[ -n "$gen" && -f "$gen" ]] && run rm -f "$gen" && info "Удалён $gen"
    done < <(manifest_get '.files[] | select(.kind == "generated") | .path')
}

restore_firewall() {
    local how
    how="$(manifest_get '.notes.firewall_kdeconnect // empty')"
    [[ -n "$how" ]] || return 0
    step "Фаервол"
    case "$how" in
        ufw)
            sudo_run ufw delete allow 1714:1764/tcp
            sudo_run ufw delete allow 1714:1764/udp
            ;;
        firewalld)
            sudo_run firewall-cmd --permanent --remove-port=1714-1764/tcp
            sudo_run firewall-cmd --permanent --remove-port=1714-1764/udp
            sudo_run firewall-cmd --reload
            ;;
    esac
    info "Правила KDE Connect ($how) убраны."
}

restore_groups() {
    step "Группы"
    local g
    while read -r g; do
        [[ -n "$g" ]] || continue
        sudo_run gpasswd -d "$USER" "$g"
    done < <(manifest_get '.groups[]')
}

packages() {
    local -a pkgs=()
    mapfile -t pkgs < <(manifest_get '.packages[]')
    if has_option --remove-faceauth || has_option --purge-packages; then
        if pkg_installed faceauth; then
            step "faceauth"
            sudo_run systemctl disable --now faceauthd.socket faceauthd.service 2>/dev/null || true
            sudo_run pacman -Rns --noconfirm faceauth
            if [[ -d /var/lib/faceauth ]] && confirm "Удалить и записанные модели лица (/var/lib/faceauth)?"; then
                sudo_run rm -rf /var/lib/faceauth
            fi
        fi
    fi
    has_option --purge-packages || return 0
    step "Пакеты"
    local -a present=() p
    for p in "${pkgs[@]}"; do [[ "$p" != faceauth ]] && pkg_installed "$p" && present+=("$p"); done
    ((${#present[@]})) || return 0
    sudo_run pacman -Rns --noconfirm "${present[@]}" ||
        warn "Часть пакетов нужна другим программам — оставлены. Список: pacman -Qqe"
}

main() {
    parse_common_args "$@"
    require_not_root
    require_sudo
    start_log uninstall
    show_plan
    snapshot "до uninstall.sh"
    restore_system_files
    restore_services
    restore_firewall
    unlink_dotfiles
    restore_groups
    packages
    if has_option --keep-state || ((DRY_RUN)); then
        note "Состояние сохранено в $STATE_DIR"
    else
        local kept
        kept="$STATE_DIR.removed-$(date +%Y%m%d-%H%M%S)"
        LOG_FILE=""
        run mv "$STATE_DIR" "$kept"
        note "Манифест и логи перенесены в $kept"
    fi
    step "Готово. Перезагрузитесь, чтобы вернулся прежний вход в систему."
}

main "$@"
