#!/usr/bin/env bash
# ADUser Service Proofer v2.1 - interactive NetExec service authentication checks
# Use only on systems and accounts you are authorized to test.
set -uo pipefail

AVAILABLE_SERVICES=(smb winrm rdp mssql wmi ssh ftp)
TARGETS=()
DOMAINS=()
USERS=()
PASSWORDS=()
SERVICES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\033[1;32m'
    DIM=$'\033[2m'
    CYAN=$'\033[1;36m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[1;31m'
    RESET=$'\033[0m'
else
    GREEN='' DIM='' CYAN='' YELLOW='' RED='' RESET=''
fi

banner() {
    printf '%s' "$GREEN"
    cat <<'ART'
         _____    ____  __  __                _____                 _
        /  _  |  / __ \/ / / /_______  _____/ ___/___  ______   __(_)_______
       / /_| | / / / / / / / ___/ _ \/ ___/\__ \/ _ \/ ___/ | / / / ___/ _ \
      / ___  |/ /_/ / /_/ (__  )  __/ /   ___/ /  __/ /   | |/ / / /__/  __/
     /_/  |_//_____/\____/____/\___/_/   /____/\___/_/    |___/_/\___/\___/
ART
    printf '%s' "$RESET"
    printf '%s\n' "${CYAN}                       [ ADUser Service Proofer v2.1 ]${RESET}"
    printf '%s\n' "${DIM}      +-- Interactive NetExec Authentication Console --+${RESET}"
    printf '\n'
}

info() { printf '%s[*]%s %s\n' "$CYAN" "$RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '%s[-]%s %s\n' "$RED" "$RESET" "$*" >&2; }

contains() {
    local needle=$1 item
    shift
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

valid_item() {
    local type=$1 value=$2
    case "$type" in
        target) [[ "$value" =~ ^[A-Za-z0-9:][A-Za-z0-9_.:%-]*$ ]] ;;
        domain) [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] ;;
        user)   [[ "$value" =~ ^[A-Za-z0-9_@.\\\$-]+$ ]] ;;
        service) contains "$value" "${AVAILABLE_SERVICES[@]}" ;;
        *) return 1 ;;
    esac
}

# Read space/comma-separated values into the named global array.
read_list() {
    local label=$1 type=$2 output_var=$3 optional=$4
    local raw item
    local -a words=() result=()
    local -n output="$output_var"

    while :; do
        read -r -p "${GREEN}aduser>${RESET} ${label}: " raw || exit 0
        raw=${raw//,/ }
        words=() result=()
        read -r -a words <<< "$raw"
        if ((${#words[@]} == 0)); then
            if [[ "$optional" == yes ]]; then
                output=()
                return 0
            fi
            fail 'At least one value is required.'
            continue
        fi
        local invalid=0
        for item in "${words[@]}"; do
            if ! valid_item "$type" "$item"; then
                fail "Invalid $type: $item"
                invalid=1
                break
            fi
            contains "$item" "${result[@]}" || result+=("$item")
        done
        ((invalid)) && continue
        output=("${result[@]}")
        return 0
    done
}

prompt_password() {
    local username=$1 output_var=$2 entered_password
    local -n output="$output_var"
    while :; do
        IFS= read -r -s -p "${GREEN}aduser>${RESET} Password for $username: " entered_password || exit 0
        printf '\n'
        if [[ -n "$entered_password" ]]; then
            output="$entered_password"
            unset entered_password
            return 0
        fi
        fail 'Password cannot be empty.'
    done
}

read_users() {
    local -a names=() new_passwords=()
    local name secret
    read_list 'Usernames (comma/space-separated)' user names no
    for name in "${names[@]}"; do
        secret=''
        prompt_password "$name" secret
        new_passwords+=("$secret")
        unset secret
    done
    USERS=("${names[@]}")
    PASSWORDS=("${new_passwords[@]}")
}

manage_users() {
    local choice name index i secret
    while :; do
        printf '\n%sUser accounts:%s\n' "$CYAN" "$RESET"
        for i in "${!USERS[@]}"; do
            printf '  %d) %s  [password set]\n' "$((i+1))" "${USERS[i]}"
        done
        printf '  a) Add user\n  e) Edit user / password\n  r) Remove user\n  x) Replace entire list\n  b) Back\n'
        read -r -p "${GREEN}aduser>${RESET} Choice: " choice || exit 0
        case "${choice,,}" in
            a)
                read -r -p 'New username: ' name || exit 0
                if ! valid_item user "$name"; then fail 'Invalid username.'; continue; fi
                if contains "$name" "${USERS[@]}"; then fail 'User already listed.'; continue; fi
                secret=''
                prompt_password "$name" secret
                USERS+=("$name")
                PASSWORDS+=("$secret")
                unset secret
                ;;
            e)
                read -r -p 'User number to edit: ' index || exit 0
                if [[ ! "$index" =~ ^[0-9]+$ ]] || ((index < 1 || index > ${#USERS[@]})); then
                    fail 'Invalid user number.'; continue
                fi
                i=$((index-1))
                read -r -p "New username [${USERS[i]}] (Enter = keep): " name || exit 0
                if [[ -n "$name" ]]; then
                    if ! valid_item user "$name"; then fail 'Invalid username.'; continue; fi
                    local j duplicate=0
                    for j in "${!USERS[@]}"; do
                        if ((j != i)) && [[ "${USERS[j]}" == "$name" ]]; then duplicate=1; fi
                    done
                    if ((duplicate)); then fail 'User already listed.'; continue; fi
                    USERS[i]=$name
                fi
                read -r -p 'Change password? [y/N]: ' choice || exit 0
                if [[ "${choice,,}" == y || "${choice,,}" == yes ]]; then
                    secret=''
                    prompt_password "${USERS[i]}" secret
                    PASSWORDS[i]=$secret
                    unset secret
                fi
                ;;
            r)
                if ((${#USERS[@]} == 1)); then fail 'Keep at least one user.'; continue; fi
                read -r -p 'User number to remove: ' index || exit 0
                if [[ ! "$index" =~ ^[0-9]+$ ]] || ((index < 1 || index > ${#USERS[@]})); then
                    fail 'Invalid user number.'; continue
                fi
                i=$((index-1))
                unset 'USERS[i]' 'PASSWORDS[i]'
                USERS=("${USERS[@]}")
                PASSWORDS=("${PASSWORDS[@]}")
                ;;
            x) read_users ;;
            b|'') return 0 ;;
            *) fail 'Unknown choice.' ;;
        esac
    done
}

attempt_count() {
    local service domain_multiplier=${#DOMAINS[@]}
    local count=0
    ((domain_multiplier > 0)) || domain_multiplier=1
    for service in "${SERVICES[@]}"; do
        if [[ "$service" == ssh || "$service" == ftp ]]; then
            ((count += ${#TARGETS[@]} * ${#USERS[@]}))
        else
            ((count += ${#TARGETS[@]} * ${#USERS[@]} * domain_multiplier))
        fi
    done
    printf '%d' "$count"
}

review() {
    local i total
    total=$(attempt_count)
    printf '\n%s+------------------- Configuration Review -------------------+%s\n' "$GREEN" "$RESET"
    printf '%s\n' ' Targets:'
    printf '   %s\n' "${TARGETS[@]}"
    printf '%s\n' ' Domains:'
    if ((${#DOMAINS[@]})); then printf '   %s\n' "${DOMAINS[@]}"; else printf '   (none / default authentication context)\n'; fi
    printf '%s\n' ' Users:'
    for i in "${!USERS[@]}"; do
        printf '   %-25s [password set]\n' "${USERS[i]}"
    done
    printf ' Services: %s\n' "${SERVICES[*]}"
    printf ' Total authentication checks: %s\n' "$total"
    printf '%s+------------------------------------------------------------+%s\n' "$GREEN" "$RESET"
    warn 'Every check is a login attempt. Account lockout policies may apply.'
    if ((${#DOMAINS[@]} > 1)); then
        warn 'Each username is tested in EVERY listed domain on each target.'
    fi
    warn 'SSH/FTP do not accept -d in NetExec, so domain entries are not used for them.'
}

run_checks() {
    local target service domain user password current_user current=0 total
    local -a args=() domain_values=()
    total=$(attempt_count)
    domain_values=("${DOMAINS[@]}")
    ((${#domain_values[@]})) || domain_values=('')
    printf '\n%s[*] Starting checks...%s\n' "$CYAN" "$RESET"

    for target in "${TARGETS[@]}"; do
        for service in "${SERVICES[@]}"; do
            if [[ "$service" == ssh || "$service" == ftp ]]; then
                for current_user in "${!USERS[@]}"; do
                    user=${USERS[current_user]}
                    password=${PASSWORDS[current_user]}
                    ((current += 1))
                    printf '\n%s========== [%d/%d] %s | %s | %s ==========%s\n' \
                        "$CYAN" "$current" "$total" "${service^^}" "$target" "$user" "$RESET"
                    if ! nxc "$service" "$target" -u "$user" -p "$password"; then
                        warn "NetExec returned a non-zero exit status ($service / $target / $user)."
                    fi
                done
            else
                for domain in "${domain_values[@]}"; do
                    for current_user in "${!USERS[@]}"; do
                        user=${USERS[current_user]}
                        password=${PASSWORDS[current_user]}
                        ((current += 1))
                        printf '\n%s========== [%d/%d] %s | %s | %s | %s ==========%s\n' \
                            "$CYAN" "$current" "$total" "${service^^}" "$target" "${domain:-NO DOMAIN}" "$user" "$RESET"
                        args=("$service" "$target")
                        [[ -z "$domain" ]] || args+=(-d "$domain")
                        args+=(-u "$user" -p "$password")
                        if ! nxc "${args[@]}"; then
                            warn "NetExec returned a non-zero exit status ($service / $target / $user)."
                        fi
                    done
                done
            fi
        done
    done
    unset password
    printf '\n%s[+] Completed %d authentication checks.%s\n' "$GREEN" "$current" "$RESET"
}

main() {
    local choice
    if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
        printf 'Usage: %s\nInteractive NetExec service checks. Requires Bash 4.3+ and nxc.\n' "$0"
        return 0
    fi
    banner
    read_list 'Target IPs / hostnames (comma/space-separated)' target TARGETS no
    read_list 'AD domains (optional; Enter = none)' domain DOMAINS yes
    read_users
    info "Available services: ${AVAILABLE_SERVICES[*]}"
    read_list 'Services (Enter = all; comma/space-separated)' service SERVICES yes
    if ((${#SERVICES[@]} == 0)); then SERVICES=("${AVAILABLE_SERVICES[@]}"); fi

    while :; do
        review
        printf '\n%sServiceProofer menu:%s\n\n' "$CYAN" "$RESET"
        printf '  %sx) [START]%s\n\n' "$GREEN" "$RESET"
        printf '  1) Edit target IP\n  2) Edit domains\n  3) Manage users / passwords\n  4) Edit services\n  5) Exit\n'
        read -r -p "${GREEN}serviceproofer>${RESET} Select: " choice || return 0
        case "$choice" in
            1) read_list 'Target IPs / hostnames' target TARGETS no ;;
            2) read_list 'AD domains (optional; Enter = none)' domain DOMAINS yes ;;
            3) manage_users ;;
            4)
                info "Available services: ${AVAILABLE_SERVICES[*]}"
                read_list 'Services (Enter = all)' service SERVICES yes
                if ((${#SERVICES[@]} == 0)); then SERVICES=("${AVAILABLE_SERVICES[@]}"); fi
                ;;
            x|X)
                if ! command -v nxc >/dev/null 2>&1; then
                    fail 'NetExec (nxc) not found in PATH.'
                    continue
                fi
                read -r -p 'Type START to confirm all checks: ' choice || return 0
                if [[ "$choice" == START ]]; then run_checks; return 0; fi
                warn 'Cancelled. You can still edit the configuration.'
                ;;
            5) info 'Exiting without running checks.'; return 0 ;;
            *) fail 'Unknown choice.' ;;
        esac
    done
}

main "$@"
