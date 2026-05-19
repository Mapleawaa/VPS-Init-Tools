#!/bin/bash
#
# init-pure-debian.sh
# Pure Debian system initialization script
# Configure a ready-to-use Server environment on a minimal Debian install
#
# Flow: Region -> Env Check -> APT Update -> User & SSH -> Security -> Optional Components -> Tuning
#

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Global constants
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.3.0"
readonly DEFAULT_SSH_PORT=2077

readonly FILES_TO_BACKUP=(
    "/etc/ssh/sshd_config"
    "/etc/fail2ban/jail.local"
    "/etc/sysctl.d/99-custom.conf"
)

readonly BASE_PACKAGES=(
    curl wget git sudo ca-certificates gnupg lsb-release
    apt-transport-https software-properties-common
    net-tools dnsutils htop tmux vim unzip jq
)

readonly SECURITY_PACKAGES=( ufw fail2ban )

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PLAIN='\033[0m'
readonly BOLD='\033[1m'

# Mirror switch script
readonly MIRROR_SCRIPT_URL="https://linuxmirrors.cn/main.sh"
readonly MIRROR_SCRIPT_FALLBACK="https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh"

# =============================================================================
# Global state
# =============================================================================

IS_CHINA=0
SSH_PORT="$DEFAULT_SSH_PORT"
USERNAME=""
USER_PASSWORD=""
USER_SHELL="/bin/bash"
BACKUP_DIR=""

# =============================================================================
# Utility functions
# =============================================================================

# -- Logging --
log_info()  { echo -e "${BLUE}[INFO]${PLAIN}  $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${PLAIN}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${PLAIN}  $*"; }
log_error() { echo -e "${RED}[FAIL]${PLAIN}  $*" >&2; }
log_step()  { echo -e "\n${CYAN}${BOLD}-- $* --${PLAIN}\n"; }
log_divider(){ echo -e "${BLUE}=============================================================${PLAIN}"; }

# -- Interaction --
confirm_yes() {
    local prompt="${1:-}"
    local answer
    read -rp "$(echo -e "${YELLOW}${prompt} [y/N]: ${PLAIN}")" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

confirm_default_yes() {
    local prompt="${1:-}"
    local answer
    read -rp "$(echo -e "${YELLOW}${prompt} [Y/n]: ${PLAIN}")" answer
    [[ "$answer" =~ ^[Nn]$ ]] && return 1
    return 0
}

# Select items from numbered list (returns raw user input string)
select_items() {
    local prompt="${1:-}"; shift
    for item in "$@"; do
        echo -e "  ${CYAN}${item}${PLAIN}"
    done
    echo ""
    read -rp "$(echo -e "${YELLOW}${prompt}: ${PLAIN}")" selection
    echo "$selection"
}

# -- System tools --
cmd_exists()   { command -v "$1" &>/dev/null; }
pkg_installed(){ dpkg -s "$1" &>/dev/null; }

install_packages() {
    local packages=("$@") to_install=()
    for pkg in "${packages[@]}"; do
        pkg_installed "$pkg" || to_install+=("$pkg")
    done
    [[ ${#to_install[@]} -eq 0 ]] && { log_ok "All packages already installed"; return 0; }
    log_info "Installing: ${to_install[*]}"
    apt-get install -y --no-install-recommends "${to_install[@]}"
}

generate_password() {
    local length="${1:-20}"
    local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%&*'
    if [[ -r /dev/urandom ]]; then
        tr -dc "$chars" < /dev/urandom | head -c "$length"
    else
        local p="" i
        for ((i = 0; i < length; i++)); do p="${p}${chars:$((RANDOM % ${#chars})):1}"; done
        echo "$p"
    fi
}

# =============================================================================
# Phase 0: Startup
# =============================================================================

show_banner() {
    log_divider
    echo -e "${BOLD}${BLUE}      Debian Server Init v${SCRIPT_VERSION}${PLAIN}"
    log_divider
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Please run as root. -> sudo $SCRIPT_NAME${PLAIN}"
        exit 1
    fi
}

# =============================================================================
# Phase 1: Region & Environment Check
# =============================================================================

detect_region() {
    log_step "Region"
    echo "  1. Overseas (default repos)"
    echo "  2. China (mirror repos)"
    local choice
    read -rp "$(echo -e "${YELLOW}Choose [1-2]: ${PLAIN}")" choice
    [[ "$choice" == "2" ]] && IS_CHINA=1
    log_ok "Selected: $([ $IS_CHINA -eq 1 ] && echo 'China' || echo 'Overseas')"
}

show_env_summary() {
    log_step "Environment Check"
    local pretty_name="Unknown" arch kernel
    arch=$(uname -m)
    kernel=$(uname -r)
    [[ -f /etc/os-release ]] && { . /etc/os-release; pretty_name="${PRETTY_NAME:-Unknown}"; }

    log_info "OS:     ${pretty_name}"
    log_info "Arch:   ${arch}"
    log_info "Kernel: ${kernel}"

    # Debian check
    if [[ "${ID:-}" != "debian" ]]; then
        log_warn "Script designed for Debian, current: ${ID:-}"
        if ! confirm_yes "Continue?"; then exit 0; fi
    fi

    # Uptime
    local uptime_s
    uptime_s=$(awk '{print int($1)}' /proc/uptime)
    if [[ $uptime_s -lt 300 ]]; then
        log_ok "Fresh boot (${uptime_s}s ago)"
    fi

    # Existing users
    local users
    users=$(awk -F: '$3>=1000 && $3!=65534{print $1}' /etc/passwd 2>/dev/null)
    [[ -n "$users" ]] && log_warn "Existing users: $users"

    # Disk
    local avail_gb
    avail_gb=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    if [[ "$avail_gb" -lt 2 ]]; then
        log_error "Disk low (${avail_gb}GB free)"
        exit 1
    fi
    log_ok "Disk: ${avail_gb}GB free"

    # Network
    if curl -s --connect-timeout 10 https://deb.debian.org > /dev/null 2>&1; then
        log_ok "Network OK"
    else
        [[ $IS_CHINA -eq 1 ]] && log_warn "Official repo unreachable, will use mirror" \
            || { if ! confirm_yes "Network error, continue?"; then exit 0; fi; }
    fi

    # Basic commands
    local missing=()
    for cmd in awk sed grep curl dpkg apt-get systemctl; do
        cmd_exists "$cmd" || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing commands: ${missing[*]}"
        exit 1
    fi
    log_ok "Basic commands OK"

    # Locale info (display only, no modifications)
    log_info "Current LANG=${LANG:-not set}"
    if cmd_exists locale; then
        local has_zh_cn has_en_us
        has_zh_cn=$(locale -a 2>/dev/null | grep -ci "zh_CN" 2>/dev/null) || has_zh_cn=0
        has_en_us=$(locale -a 2>/dev/null | grep -ci "en_US.utf" 2>/dev/null) || has_en_us=0
        if [[ "${has_zh_cn}" -gt 0 ]]; then
            log_warn "zh_CN locale detected (no system change)"
        fi
        if [[ "${has_en_us}" -gt 0 ]]; then
            log_ok "en_US.UTF-8 available"
        fi
    else
        log_warn "locale command not available, skip locale check"
    fi

    return 0
}

# =============================================================================
# Phase 2: Backup & APT
# =============================================================================

create_backups() {
    BACKUP_DIR="/root/init-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    local count=0
    for file in "${FILES_TO_BACKUP[@]}"; do
        [[ -f "$file" ]] || continue
        local dest="${BACKUP_DIR}$(dirname "$file")"
        mkdir -p "$dest"
        cp -a "$file" "${dest}/"
        log_info "Backup: ${file}"
        ((count++)) || true
    done
    log_ok "Backed up ${count} files -> ${BACKUP_DIR}"
}

configure_apt_sources() {
    log_step "APT Sources"

    if [[ $IS_CHINA -eq 1 ]]; then
        log_info "Downloading mirror switch script (linuxmirrors.cn)..."
        local script_url="$MIRROR_SCRIPT_URL"
        local tmp_script="/tmp/linuxmirrors.sh"

        if ! curl -fsSL "$script_url" -o "$tmp_script" 2>/dev/null; then
            log_warn "Primary mirror script unreachable, trying fallback..."
            script_url="$MIRROR_SCRIPT_FALLBACK"
            if ! curl -fsSL "$script_url" -o "$tmp_script" 2>/dev/null; then
                log_error "Failed to download mirror script, skip mirror switch"
                return 0
            fi
        fi

        log_info "Running mirror switch script..."
        # --pure-mode: clean output
        # --lang en: English output (avoid CJK garble in TTY)
        bash "$tmp_script" --pure-mode --lang en \
            || { log_warn "Mirror switch script exited with warnings"; }

        rm -f "$tmp_script"
        log_ok "Mirror sources configured via linuxmirrors.cn"
    else
        log_info "Keeping default official repos"
    fi
}

update_apt() {
    log_step "APT Update & Base Tools"
    log_info "Updating index..."
    apt-get update -y || { log_error "apt update failed"; exit 1; }
    apt-get upgrade -y || log_warn "upgrade issues, continuing"

    install_packages "${BASE_PACKAGES[@]}"
    install_packages "${SECURITY_PACKAGES[@]}"
    log_ok "Base tools installed"
}

# =============================================================================
# Phase 3: User & SSH
# =============================================================================

create_user() {
    log_step "Create User"

    local input_username
    while true; do
        read -rp "$(echo -e "${YELLOW}Username: ${PLAIN}")" input_username
        input_username=$(echo "$input_username" | xargs)
        [[ -z "$input_username" ]] && { log_error "Empty"; continue; }

        USERNAME=$(echo "$input_username" | tr '[:upper:]' '[:lower:]')
        if ! echo "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
            log_error "Invalid (lowercase, digits, _/-)"
            continue
        fi
        if [[ "$USERNAME" == "root" || "$USERNAME" == "admin" || "$USERNAME" == "debian" ]]; then
            log_warn "'${USERNAME}' is reserved"
            confirm_yes "Use anyway?" || continue
        fi
        id "$USERNAME" &>/dev/null && { log_warn "User exists, reusing"; break; }
        break
    done

    if ! id "$USERNAME" &>/dev/null; then
        # Password
        read -rsp "$(echo -e "${YELLOW}Password (Enter=random): ${PLAIN}")" USER_PASSWORD
        echo
        [[ -z "$USER_PASSWORD" ]] && USER_PASSWORD=$(generate_password 20)

        # Shell
        echo "  1. bash  2. zsh"
        local shell_choice
        read -rp "$(echo -e "${YELLOW}Shell [1-2]: ${PLAIN}")" shell_choice
        [[ "$shell_choice" == "2" ]] && USER_SHELL="/bin/zsh"

        useradd -m -s "$USER_SHELL" "$USERNAME"
        echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
        log_ok "User ${USERNAME} created"
    else
        USER_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
        log_ok "Reusing user ${USERNAME}"
    fi

    # sudo
    if ! usermod -aG sudo "$USERNAME" 2>/dev/null; then
        groupadd sudo 2>/dev/null || true
        usermod -aG sudo "$USERNAME"
    fi
    local ng="${USERNAME}_nopasswd"
    groupadd "$ng" 2>/dev/null || true
    usermod -aG "$ng" "$USERNAME"
    echo "%${ng} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USERNAME}"
    chmod 440 "/etc/sudoers.d/${USERNAME}"
    log_ok "sudo NOPASSWD configured"
}

configure_ssh() {
    log_step "Configure SSH"

    # Ensure sshd is running
    if ! cmd_exists sshd && ! pkg_installed openssh-server; then
        install_packages openssh-server
    fi
    systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null
    systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null \
        || { log_error "SSH start failed"; exit 1; }
    log_ok "SSH service running"

    # Port
    read -rp "$(echo -e "${YELLOW}SSH port (default ${DEFAULT_SSH_PORT}): ${PLAIN}")" port_input
    if [[ -n "$port_input" ]]; then
        if [[ "$port_input" =~ ^[0-9]+$ && "$port_input" -ge 1 && "$port_input" -le 65535 ]]; then
            SSH_PORT="$port_input"
        else
            log_warn "Invalid port, using default"
        fi
    fi

    # Public key (required)
    read -rp "$(echo -e "${YELLOW}Paste SSH public key (required): ${PLAIN}")" USER_PUB_KEY
    [[ -z "$USER_PUB_KEY" ]] && { log_error "Key required to prevent lockout"; exit 1; }

    if ! echo "$USER_PUB_KEY" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|sk-ssh-ed25519|sk-ecdsa-sha2-nistp) '; then
        log_warn "Key format looks non-standard"
        confirm_yes "Use anyway?" || exit 1
    fi

    # authorized_keys
    local home="/home/${USERNAME}"
    mkdir -p "${home}/.ssh"
    echo "$USER_PUB_KEY" > "${home}/.ssh/authorized_keys"
    chmod 700 "${home}/.ssh" && chmod 600 "${home}/.ssh/authorized_keys"
    chown -R "${USERNAME}:${USERNAME}" "${home}/.ssh"

    # sshd_config - only modify essential settings
    local cfg="/etc/ssh/sshd_config"
    _sshd_set() {
        local key="$1" val="$2"
        if grep -qE "^#?\s*${key}" "$cfg"; then
            sed -i "s/^#\?\s*${key}.*/${key} ${val}/" "$cfg"
        else
            echo "${key} ${val}" >> "$cfg"
        fi
    }
    _sshd_set Port "${SSH_PORT}"
    _sshd_set PermitRootLogin "no"
    _sshd_set PasswordAuthentication "no"
    _sshd_set PubkeyAuthentication "yes"
    _sshd_set PermitEmptyPasswords "no"
    _sshd_set MaxAuthTries "3"
    _sshd_set ClientAliveInterval "300"
    _sshd_set ClientAliveCountMax "2"
    _sshd_set X11Forwarding "no"

    log_ok "SSH configured (port: ${SSH_PORT})"
}

# =============================================================================
# Phase 4: Security
# =============================================================================

configure_firewall() {
    log_step "Configure Firewall"
    ufw default deny incoming && ufw default allow outgoing
    ufw allow "${SSH_PORT}/tcp" comment "SSH"
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"

    if confirm_yes "Open additional ports?"; then
        while true; do
            read -rp "$(echo -e "${YELLOW}Port (e.g. 8080/tcp, empty to finish): ${PLAIN}")" ep
            [[ -z "$ep" ]] && break
            ufw allow "$ep" comment "Custom"
        done
    fi

    ufw --force enable
    log_ok "UFW enabled"
    ufw status numbered
}

configure_fail2ban() {
    log_step "Configure Fail2Ban"
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
EOF
    systemctl enable --now fail2ban
    log_ok "Fail2Ban started"
}

# =============================================================================
# Phase 5: Optional Components
# =============================================================================

show_component_menu() {
    log_step "Optional Components"
    echo -e "  ${CYAN}-- Enter numbers separated by spaces, Enter to skip all --${PLAIN}"
    echo ""
    echo -e "  ${BOLD}[1]${PLAIN} ZSH + Oh My Zsh"
    echo -e "  ${BOLD}[2]${PLAIN} Docker"
    echo -e "  ${BOLD}[3]${PLAIN} K3s (Lightweight Kubernetes)"
    echo -e "  ${BOLD}[4]${PLAIN} Monitoring (btop / fastfetch)"
    echo -e "  ${BOLD}[5]${PLAIN} Server Panel (1Panel / BT.CN / CasaOS)"
    echo -e "  ${BOLD}[6]${PLAIN} WAF (SafeLine / BunkerWeb)"
    echo ""
}

# -- ZSH --

install_zsh() {
    log_step "ZSH + Oh My Zsh"
    install_packages zsh

    if [[ "$USER_SHELL" != "/bin/zsh" ]]; then
        chsh -s /bin/zsh "$USERNAME"
        USER_SHELL="/bin/zsh"
    fi

    local home="/home/${USERNAME}"
    local omz_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    [[ $IS_CHINA -eq 1 ]] && omz_url="https://install.ohmy.schue.we.cn/ohmyzsh.sh"

    log_info "Installing Oh My Zsh..."
    sudo -u "$USERNAME" sh -c "$(curl -fsSL "$omz_url")" "" --unattended \
        || log_warn "Oh My Zsh install failed"

    local custom="${home}/.oh-my-zsh/custom"
    if [[ -d "$custom" ]]; then
        local git_base="https://github.com"
        [[ $IS_CHINA -eq 1 ]] && git_base="https://ghfast.top/https://github.com"

        [[ ! -d "${custom}/plugins/zsh-autosuggestions" ]] && \
            sudo -u "$USERNAME" git clone --depth=1 "${git_base}/zsh-users/zsh-autosuggestions" \
                "${custom}/plugins/zsh-autosuggestions" 2>/dev/null || true
        [[ ! -d "${custom}/plugins/zsh-syntax-highlighting" ]] && \
            sudo -u "$USERNAME" git clone --depth=1 "${git_base}/zsh-users/zsh-syntax-highlighting" \
                "${custom}/plugins/zsh-syntax-highlighting" 2>/dev/null || true

        local zshrc="${home}/.zshrc"
        if [[ -f "$zshrc" ]]; then
            sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$zshrc"
            sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' "$zshrc"
            chown "${USERNAME}:${USERNAME}" "$zshrc"
        fi
    fi
    log_ok "ZSH configured"
}

# -- Docker --

install_docker() {
    log_step "Docker"
    if cmd_exists docker; then
        log_ok "Docker already installed"; docker --version
    else
        log_info "Installing Docker..."
        install_packages gnupg2
        rm -rf /etc/apt/keyrings/docker.gpg 2>/dev/null; mkdir -p /etc/apt/keyrings

        local gpg_url="https://download.docker.com/linux/debian/gpg"
        local repo_url="https://download.docker.com/linux/debian"
        [[ $IS_CHINA -eq 1 ]] && { gpg_url="https://mirrors.aliyun.com/docker-ce/linux/debian/gpg"
                                    repo_url="https://mirrors.aliyun.com/docker-ce/linux/debian"; }

        curl -fsSL "$gpg_url" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${repo_url} \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

        apt-get update -y -qq
        install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable --now docker

        if docker info &>/dev/null; then
            log_ok "Docker installed"; docker --version
        else
            log_error "Docker failed to start"; return 1
        fi
    fi
    usermod -aG docker "$USERNAME"
    log_ok "User added to docker group"
}

# -- K3s --

install_k3s() {
    log_step "K3s"
    if cmd_exists k3s; then
        log_ok "K3s already installed"; k3s --version 2>/dev/null | head -1
        return 0
    fi

    local k3s_url="https://get.k3s.io"
    if [[ $IS_CHINA -eq 1 ]]; then
        k3s_url="https://rancher-mirror.rancher.cn/k3s/k3s-install.sh"
    fi

    log_info "Installing K3s..."

    if [[ $IS_CHINA -eq 1 ]]; then
        export INSTALL_K3S_MIRROR="cn"
    fi

    curl -sfL "$k3s_url" | sh -s - --disable=traefik || {
        log_error "K3s install failed"; return 1
    }
    systemctl enable k3s
    log_ok "K3s installed"
    k3s --version 2>/dev/null | head -1
    log_info "Config: /etc/rancher/k3s/k3s.yaml"
    log_info "Check nodes: k3s kubectl get nodes"
}

# -- Monitoring --

install_monitoring() {
    log_step "Monitoring Tools"
    install_packages btop

    if apt-cache show fastfetch &>/dev/null; then
        install_packages fastfetch
    else
        install_packages neofetch
    fi

    # Write to shell rc
    local home="/home/${USERNAME}" rc
    rc="${home}/.bashrc"
    [[ "$USER_SHELL" == "/bin/zsh" ]] && rc="${home}/.zshrc"
    local cmd="fastfetch"
    pkg_installed fastfetch || cmd="neofetch"
    [[ -f "$rc" ]] && ! grep -q "$cmd" "$rc" && { echo "$cmd" >> "$rc"; chown "${USERNAME}:${USERNAME}" "$rc"; }

    log_ok "Monitoring tools installed"
}

# -- Server Panel --

install_panel() {
    log_step "Server Panel"
    echo ""
    echo -e "  1. 1Panel     (Modern open-source panel)"
    echo -e "  2. BT.CN      (Classic management panel)"
    echo -e "  3. CasaOS     (Lightweight home cloud)"
    echo ""
    read -rp "$(echo -e "${YELLOW}Choose [1-3]: ${PLAIN}")" choice

    case "$choice" in
        1) _install_1panel ;;
        2) _install_bt ;;
        3) _install_casaos ;;
        *) log_warn "Invalid choice, skipped" ;;
    esac
}

_install_1panel() {
    log_info "Installing 1Panel..."
    local url="https://resource.fit2cloud.com/1panel/package/quick_start.sh"
    curl -sSL "$url" -o /tmp/1panel_quick_start.sh \
        && bash /tmp/1panel_quick_start.sh \
        && { log_ok "1Panel installed"; return 0; }
    log_error "1Panel install failed"
}

_install_bt() {
    log_info "Installing BT.CN Panel..."
    local url="https://download.bt.cn/install/install-ubuntu_6.0.sh"
    wget -O /tmp/bt_install.sh "$url" --timeout=30 -q \
        && yes | bash /tmp/bt_install.sh ed8484bec \
        && { log_ok "BT.CN Panel installed"; return 0; }
    log_error "BT.CN Panel install failed"
}

_install_casaos() {
    log_info "Installing CasaOS..."
    curl -fsSL https://get.casaos.io | bash \
        && { log_ok "CasaOS installed"; return 0; }
    log_error "CasaOS install failed"
}

# -- WAF --

install_waf() {
    log_step "WAF"
    echo ""
    echo -e "  1. SafeLine   (Safeline by Chaitin)"
    echo -e "  2. BunkerWeb (Open-source WAF)"
    echo ""
    read -rp "$(echo -e "${YELLOW}Choose [1-2]: ${PLAIN}")" choice

    case "$choice" in
        1) _install_safeline ;;
        2) _install_bunkerweb ;;
        *) log_warn "Invalid choice, skipped" ;;
    esac
}

_install_safeline() {
    log_info "Installing SafeLine..."
    if ! cmd_exists docker; then
        log_error "SafeLine requires Docker"
        return 1
    fi

    bash -c "$(curl -fsSL https://waf-ce.chaitin.cn/release/latest/setup.sh)" \
        && { log_ok "SafeLine installed"
             log_info "Dashboard: http://<IP>:9443"
             return 0; }
    log_error "SafeLine install failed"
}

_install_bunkerweb() {
    log_info "Installing BunkerWeb..."
    curl -sSL https://get.bunkerweb.io | bash \
        && { log_ok "BunkerWeb installed"
             log_info "Dashboard: http://<IP>:8080"
             return 0; }
    log_error "BunkerWeb install failed"
}

# -- Component dispatcher --

run_selected_components() {
    local selection
    selection=$(select_items "Enter numbers (space-separated, Enter to skip)")

    [[ -z "$selection" ]] && { log_info "Skipped optional components"; return 0; }

    # Normalize: support "1 2 3" or "123" or "1,2,3"
    local items
    items=$(echo "$selection" | tr -s ', ' ' ')

    for item in $items; do
        case "$item" in
            1) install_zsh ;;
            2) install_docker ;;
            3) install_k3s ;;
            4) install_monitoring ;;
            5) install_panel ;;
            6) install_waf ;;
            *) log_warn "Unknown option: ${item}" ;;
        esac
    done
}

# =============================================================================
# Phase 6: System Tuning & Wrap-up
# =============================================================================

system_tuning() {
    log_step "System Tuning"

    # Timezone
    if cmd_exists timedatectl; then
        local tz
        tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")
        log_info "Timezone: ${tz:-UTC}"
        if confirm_yes "Change timezone?"; then
            echo "  1. Asia/Shanghai  2. Asia/Tokyo  3. America/New_York  4. Europe/London  5. UTC  6. Custom"
            read -rp "$(echo -e "${YELLOW}Choose [1-6]: ${PLAIN}")" tzc
            case "$tzc" in
                1) timedatectl set-timezone Asia/Shanghai ;;
                2) timedatectl set-timezone Asia/Tokyo ;;
                3) timedatectl set-timezone America/New_York ;;
                4) timedatectl set-timezone Europe/London ;;
                5) timedatectl set-timezone UTC ;;
                6) read -rp "TZ: " ctz; timedatectl set-timezone "$ctz" 2>/dev/null ;;
            esac
        fi
    fi

    # vim
    [[ ! -f /etc/vim/vimrc.local ]] && cat > /etc/vim/vimrc.local <<'EOF'
set nocompatible encoding=utf-8 fileencodings=utf-8,gbk,latin1
set number autoindent tabstop=4 shiftwidth=4 expandtab
set hlsearch incsearch syntax on
EOF

    # limits
    if ! grep -q '\* soft nofile 65535' /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<'EOF'

# Init script tuning
*  soft nofile 65535
*  hard nofile 65535
*  soft nproc  65535
*  hard nproc  65535
root soft nofile 65535
root hard nofile 65535
EOF
    fi

    # sysctl
    cat > /etc/sysctl.d/99-custom.conf <<'EOF'
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF
    sysctl --system > /dev/null 2>&1

    log_ok "System tuning done"
}

show_summary() {
    echo ""
    log_divider
    echo -e "${BOLD}${GREEN}  Initialization Complete${PLAIN}"
    log_divider
    echo ""
    echo -e "  User:     ${GREEN}${USERNAME}${PLAIN}"
    [[ -n "${USER_PASSWORD:-}" ]] && echo -e "  Password: ${YELLOW}${USER_PASSWORD}${PLAIN}"
    echo -e "  Shell:    ${CYAN}${USER_SHELL}${PLAIN}"
    echo -e "  SSH Port: ${RED}${SSH_PORT}${PLAIN}"
    echo ""
    echo -e "  ${YELLOW}Notes:${PLAIN}"
    echo -e "    1. SSH port: ${RED}${SSH_PORT}${PLAIN}"
    echo -e "    2. Root/password login disabled"
    echo -e "    3. Connect: ${CYAN}ssh -p ${SSH_PORT} ${USERNAME}@<IP>${PLAIN}"
    echo ""
    echo -e "  ${RED}*** Do NOT close this session! Test connection in a new terminal first! ***${PLAIN}"
    echo ""
    log_divider
}

restart_ssh_prompt() {
    echo ""
    if confirm_yes "Restart SSH now?"; then
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
        log_ok "SSH restarted, test connection now"
    else
        log_warn "Run manually: systemctl restart ssh"
    fi
}

# =============================================================================
# Main flow
# =============================================================================

main() {
    # Phase 0
    show_banner
    check_root

    # Phase 1
    detect_region
    show_env_summary

    # Phase 2
    create_backups
    configure_apt_sources
    update_apt

    # Phase 3
    create_user
    configure_ssh

    # Phase 4
    configure_firewall
    configure_fail2ban

    # Phase 5
    show_component_menu
    run_selected_components

    # Phase 6
    system_tuning
    show_summary
    restart_ssh_prompt
}

main "$@"
