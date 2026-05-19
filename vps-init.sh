#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="1.0.0"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly PLAIN='\033[0m'
readonly BOLD='\033[1m'

# Global state
REGION=""           # CN or country code (JP, US, DE, etc.)
ARCH=""             # x86_64, aarch64, etc.
OS_NAME=""          # Debian, Ubuntu, etc.
OS_VERSION=""       # 12, 22.04, etc.
OS_CODENAME=""      # bookworm, jammy, etc.
BEST_MIRROR=""      # chosen mirror URL
SSH_PORT=""
USERNAME=""
USER_PUB_KEY=""
HOSTNAME=""
TIMEZONE=""
HAS_SWAP=0
SWAP_TYPE=""
CPU_STRONG=0
RAM_MB=0
DISK_GB=0
BANDWIDTH_Mbps=0
LATENCY_MS=0
BBR_INSTALLED=0
CLOUDFLARED_INSTALLED=0
REPORT_FILE="/root/setup-report.log"
START_TIME=""

# Country → Debian GeoDNS mirror: uses ftp.<cc>.debian.org which auto-routes to
# the best regional mirror via DNS.  Fallback is deb.debian.org (global GeoDNS).

# =============================================================================
# Utility Functions
# =============================================================================

log_info()  { echo -e "${BLUE}[INFO]${PLAIN}  $*"; }
log_ok()    { echo -e "${GREEN}[ OK ]${PLAIN}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${PLAIN}  $*"; }
log_error() { echo -e "${RED}[FAIL]${PLAIN}  $*" >&2; }
log_step()  { echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════${PLAIN}"; echo -e "${CYAN}${BOLD}  $*${PLAIN}"; echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${PLAIN}\n"; }
log_divider(){ echo -e "${BLUE}───────────────────────────────────────────────────────────${PLAIN}"; }

confirm_yes() {
    local prompt="${1:-Continue?}"
    local answer
    read -rp "$(echo -e "${YELLOW}${prompt} [y/N]: ${PLAIN}")" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

cmd_exists() { command -v "$1" &>/dev/null; }
pkg_installed() { dpkg -s "$1" &>/dev/null; }

install_packages() {
    local packages=("$@") to_install=()
    for pkg in "${packages[@]}"; do
        pkg_installed "$pkg" || to_install+=("$pkg")
    done
    [[ ${#to_install[@]} -eq 0 ]] && { log_ok "All packages already installed"; return 0; }
    log_info "Installing: ${to_install[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${to_install[@]}"
}

show_banner() {
    echo ""
    echo -e "${BLUE}${BOLD}  ╔══════════════════════════════════════════════════════╗${PLAIN}"
    echo -e "${BLUE}${BOLD}  ║          VPS Init Script v${SCRIPT_VERSION}                 ║${PLAIN}"
    echo -e "${BLUE}${BOLD}  ║     Automated Server Initialization & Hardening    ║${PLAIN}"
    echo -e "${BLUE}${BOLD}  ╚══════════════════════════════════════════════════════╝${PLAIN}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Must run as root"
        exit 1
    fi
}

# =============================================================================
# Phase 1 - Environment Detection
# =============================================================================

phase1_detect_env() {
    log_step "Phase 1 - Environment Detection"

    # 1a. Detect OS Distro
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
        log_info "OS: ${PRETTY_NAME:-$OS_NAME $OS_VERSION}"
    else
        log_error "Cannot detect OS (/etc/os-release missing)"
        exit 1
    fi

    if [[ "$OS_NAME" != "debian" && "$OS_NAME" != "ubuntu" ]]; then
        log_warn "Script target: Debian/Ubuntu. Current: $OS_NAME"
        confirm_yes "Continue anyway?" || exit 1
    fi

    # 1b. Detect Architecture
    ARCH=$(uname -m)
    log_info "Arch: $ARCH"

    # 1c. Detect Region via Cloudflare CGI
    log_info "Detecting region via Cloudflare trace..."
    local cf_trace
    if cf_trace=$(curl -s --connect-timeout 10 "https://www.dyson.cn/cdn-cgi/trace" 2>/dev/null); then
        local loc
        loc=$(echo "$cf_trace" | grep "^loc=" | cut -d= -f2)
        if [[ "$loc" == "CN" ]]; then
            REGION="CN"
            log_ok "Region: China (CN)"
        elif [[ -n "$loc" ]]; then
            REGION="$loc"
            log_ok "Region: $loc (Overseas)"
        else
            REGION="Global"
            log_warn "Could not determine country, defaulting to Global"
        fi
    else
        # Fallback: ask user
        log_warn "Cloudflare trace failed, manual input required"
        echo "  1. China (CN)"
        echo "  2. Overseas"
        local choice
        read -rp "$(echo -e "${YELLOW}Choose [1-2]: ${PLAIN}")" choice
        if [[ "$choice" == "1" ]]; then
            REGION="CN"
        else
            read -rp "$(echo -e "${YELLOW}Enter your country code (e.g. JP, US, DE): ${PLAIN}")" REGION
            REGION=$(echo "$REGION" | tr '[:lower:]' '[:upper:]')
            [[ -z "$REGION" ]] && REGION="Global"
        fi
    fi

    # 1d. Collect hardware info early
    RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
    log_info "RAM: ${RAM_MB}MB | Disk: ${DISK_GB}GB"
}

# =============================================================================
# Phase 2 - Base Initialization
# =============================================================================

# Country → Debian GeoDNS mirror
country_mirror() {
    local cc="$1"
    # Normalize: uppercase, strip anything after dash
    cc=$(echo "$cc" | tr '[:lower:]' '[:upper:]' | cut -d- -f1)
    case "$cc" in
        AD|AE|AF|AG|AI|AL|AM|AO|AQ|AR|AS|AT|AW|AX|AZ|BA|BB|BD|BE|BF|BG|BH|BI|BJ|BL|BM|BN|BO|BQ|BR|BS|BT|BV|BW|BY|BZ|CA|CC|CD|CF|CG|CH|CI|CK|CL|CM|CN|CO|CR|CU|CV|CW|CX|CY|CZ|DE|DJ|DK|DM|DO|DZ|EC|EE|EG|EH|ER|ES|ET|FI|FJ|FK|FM|FO|FR|GA|GB|GD|GE|GF|GG|GH|GI|GL|GM|GN|GP|GQ|GR|GS|GT|GU|GW|GY|HK|HM|HN|HR|HT|HU|ID|IE|IL|IM|IN|IO|IQ|IR|IS|IT|JE|JM|JO|JP|KE|KG|KH|KI|KM|KN|KP|KR|KW|KY|KZ|LA|LB|LC|LI|LK|LR|LS|LT|LU|LV|LY|MA|MC|MD|ME|MF|MG|MH|MK|ML|MM|MN|MO|MP|MQ|MR|MS|MT|MU|MV|MW|MX|MY|MZ|NA|NC|NE|NF|NG|NI|NL|NO|NP|NR|NU|NZ|OM|PA|PE|PF|PG|PH|PK|PL|PM|PN|PR|PS|PT|PW|PY|QA|RE|RO|RS|RU|RW|SA|SB|SC|SD|SE|SG|SH|SI|SJ|SK|SL|SM|SN|SO|SR|SS|ST|SV|SX|SY|SZ|TC|TD|TF|TG|TH|TJ|TK|TL|TM|TN|TO|TR|TT|TV|TW|TZ|UA|UG|UM|US|UY|UZ|VA|VC|VE|VG|VI|VN|VU|WF|WS|YE|YT|ZA|ZM|ZW) echo "http://ftp.${cc,,}.debian.org/debian/" ;;
        *) echo "http://deb.debian.org/debian/" ;;
    esac
}

configure_mirror_cn() {
    log_info "Launching mirror switch script (linuxmirrors.cn)..."
    log_info "Follow the interactive prompts to select your preferred mirror."
    bash <(curl -sSL "https://linuxmirrors.cn/main.sh") || {
        log_warn "Mirror switch script failed, using fallback"
        local release_name="${OS_CODENAME:-bookworm}"
        if [[ "$OS_NAME" == "ubuntu" ]]; then
            cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/ubuntu/ $release_name main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ $release_name-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ $release_name-backports main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ $release_name-security main restricted universe multiverse
EOF
            BEST_MIRROR="https://mirrors.aliyun.com/ubuntu/"
        else
            cat > /etc/apt/sources.list <<EOF
deb https://mirrors.aliyun.com/debian/ $release_name main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian/ $release_name-updates main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian/ $release_name-backports main contrib non-free non-free-firmware
deb https://mirrors.aliyun.com/debian-security $release_name-security main contrib non-free non-free-firmware
EOF
            BEST_MIRROR="https://mirrors.aliyun.com/debian/"
        fi
        log_ok "Fallback: configured Aliyun mirror for $OS_NAME"
        return
    }
    BEST_MIRROR="mirror set by linuxmirrors.cn"
    log_ok "Mirror configured via linuxmirrors.cn"
}

configure_mirror_overseas() {
    BEST_MIRROR=$(country_mirror "$REGION")
    log_info "Using GeoDNS mirror for $REGION: $BEST_MIRROR"

    local release_name="${OS_CODENAME:-bookworm}"

    # Disable conflicting stock Debian repo files in sources.list.d
    local f
    for f in /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" ]] || continue
        if grep -qE '^(deb|deb-src)\s' "$f" 2>/dev/null; then
            mv "$f" "${f}.disabled" 2>/dev/null || true
        fi
    done

    if [[ "$OS_NAME" == "ubuntu" ]]; then
        cat > /etc/apt/sources.list <<EOF
deb $BEST_MIRROR $release_name main restricted universe multiverse
deb $BEST_MIRROR $release_name-updates main restricted universe multiverse
deb $BEST_MIRROR $release_name-backports main restricted universe multiverse
deb $BEST_MIRROR $release_name-security main restricted universe multiverse
EOF
    else
        local sec_url="${BEST_MIRROR%debian/}debian-security"
        cat > /etc/apt/sources.list <<EOF
deb $BEST_MIRROR $release_name main contrib non-free non-free-firmware
deb $BEST_MIRROR $release_name-updates main contrib non-free non-free-firmware
deb $BEST_MIRROR $release_name-backports main contrib non-free non-free-firmware
deb $sec_url $release_name-security main contrib non-free non-free-firmware
EOF
    fi
    log_ok "Mirror configured: $BEST_MIRROR"
}

phase2_base_init() {
    log_step "Phase 2 - Base Initialization"

    # 2a. Configure mirror based on region
    if [[ "$REGION" == "CN" ]]; then
        configure_mirror_cn
    else
        configure_mirror_overseas
    fi

    # 2b. System update
    log_info "Updating package lists..."
    apt-get update -y || { log_error "apt update failed"; exit 1; }
    log_info "Upgrading packages..."
    apt-get upgrade -y || log_warn "Upgrade had issues, continuing"

    # 2c. Install base tools
    install_packages \
        curl wget git sudo ca-certificates gnupg lsb-release \
        apt-transport-https \
        net-tools dnsutils htop tmux vim unzip jq \
        bc sysbench python3 ufw fail2ban openssh-server

    log_ok "Base tools installed"

    # 2d. Configure SSH user and keys
    log_step "SSH Configuration"

    # Ask for username; empty = retain current root-based config, skip user setup
    USERNAME=""
    while [[ -z "$USERNAME" ]]; do
        read -rp "$(echo -e "${YELLOW}Username (Enter=skip user setup): ${PLAIN}")" USERNAME
        USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]' | xargs)
        [[ -z "$USERNAME" ]] && break
        if ! echo "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
            log_error "Invalid username (lowercase, digits, _/- only)"
            USERNAME=""
        fi
    done

    # SSH port (always prompt)
    read -rp "$(echo -e "${YELLOW}SSH Port (default 2077): ${PLAIN}")" SSH_PORT
    SSH_PORT="${SSH_PORT:-2077}"

    # Hardening always applies regardless of user setup
    local cfg="/etc/ssh/sshd_config"
    [[ -f "$cfg" ]] && cp "$cfg" "${cfg}.bak.$(date +%Y%m%d_%H%M%S)"

    _sshd_set() {
        local key="$1" val="$2"
        if grep -qE "^#?\s*${key}" "$cfg" 2>/dev/null; then
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

    systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
    log_ok "SSH hardened (port: $SSH_PORT)"

    if [[ -n "$USERNAME" ]]; then
        # Create user if not exists
        if ! id "$USERNAME" &>/dev/null; then
            useradd -m -s /bin/bash "$USERNAME"
            log_ok "User $USERNAME created"
        else
            log_ok "User $USERNAME already exists"
        fi

        # Sudo NOPASSWD
        local sudogrp="${USERNAME}_nopasswd"
        groupadd "$sudogrp" 2>/dev/null || true
        usermod -aG sudo "$USERNAME" 2>/dev/null || true
        usermod -aG "$sudogrp" "$USERNAME"
        echo "%${sudogrp} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USERNAME}"
        chmod 440 "/etc/sudoers.d/${USERNAME}"

        # Check if SSH key already exists for this user
        local home="/home/${USERNAME}"
        local key_found=0
        if [[ -f "${home}/.ssh/authorized_keys" ]]; then
            local key_count
            key_count=$(grep -cvE '^\s*(#|$)' "${home}/.ssh/authorized_keys" 2>/dev/null || echo "0")
            if [[ "$key_count" -gt 0 ]]; then
                log_ok "SSH key already configured for ${USERNAME} (${key_count} key(s))"
                key_found=1
            fi
        fi

        if [[ $key_found -eq 0 ]]; then
            read -rp "$(echo -e "${YELLOW}SSH Public Key (Enter=skip): ${PLAIN}")" USER_PUB_KEY
            if [[ -n "$USER_PUB_KEY" ]]; then
                mkdir -p "${home}/.ssh"
                echo "$USER_PUB_KEY" > "${home}/.ssh/authorized_keys"
                chmod 700 "${home}/.ssh" && chmod 600 "${home}/.ssh/authorized_keys"
                chown -R "${USERNAME}:${USERNAME}" "${home}/.ssh"
                log_ok "SSH key added for $USERNAME"
            else
                log_warn "No SSH key provided — you may be locked out after reboot if password auth is also disabled"
            fi
        fi
    else
        log_info "User setup skipped, root-based config retained"
    fi

    # 2f. Set hostname and timezone
    read -rp "$(echo -e "${YELLOW}Hostname (default: $(hostname)): ${PLAIN}")" HOSTNAME
    if [[ -n "$HOSTNAME" ]]; then
        hostnamectl set-hostname "$HOSTNAME"
        log_ok "Hostname set to $HOSTNAME"
    else
        HOSTNAME=$(hostname)
    fi

    log_info "Setting timezone..."
    # Auto-select timezone based on region
    case "$REGION" in
        CN|HK|TW|MO|SG|MY|PH|TH|ID|VN) TIMEZONE="Asia/Shanghai" ;;
        JP|KR) TIMEZONE="Asia/Tokyo" ;;
        IN) TIMEZONE="Asia/Kolkata" ;;
        GB|UK|IE|PT) TIMEZONE="Europe/London" ;;
        DE|NL|FR|CH|AT|BE|PL|IT|ES|NO|SE|DK|FI) TIMEZONE="Europe/Berlin" ;;
        RU) TIMEZONE="Europe/Moscow" ;;
        US|CA|MX) TIMEZONE="America/New_York" ;;
        AU) TIMEZONE="Australia/Sydney" ;;
        NZ) TIMEZONE="Pacific/Auckland" ;;
        *) TIMEZONE="UTC" ;;
    esac
    timedatectl set-timezone "$TIMEZONE" 2>/dev/null || log_warn "Could not set timezone"
    log_ok "Timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || echo $TIMEZONE)"
}

# =============================================================================
# Phase 3 - Security Hardening
# =============================================================================

phase3_security() {
    log_step "Phase 3 - Security Hardening"

    # 3a. UFW
    log_info "Configuring UFW..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${SSH_PORT}/tcp" comment "SSH"
    ufw --force enable
    log_ok "UFW enabled (default deny, SSH:$SSH_PORT allowed)"

    # 3b. fail2ban
    log_info "Configuring fail2ban..."
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
    log_ok "fail2ban started"

    # 3c. CrowdSec
    log_info "Installing CrowdSec..."
    if cmd_exists crowdsec; then
        log_ok "CrowdSec already installed"
    else
        curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
        install_packages crowdsec || {
            log_warn "CrowdSec install via packagecloud failed, trying alternative..."
            # Fallback: direct apt from crowdsec repo
            curl -sSL https://raw.githubusercontent.com/crowdsecurity/crowdsec/master/scripts/install_crowdsec.sh | bash || {
                log_warn "CrowdSec installation failed, skipping"
            }
        }
    fi

    if cmd_exists crowdsec; then
        log_ok "CrowdSec installed"

        # 3d. Load CrowdSec scenarios
        log_info "Loading CrowdSec scenarios..."
        cscli scenarios install crowdsecurity/ssh-bf crowdsecurity/http-bf crowdsecurity/http-crawl-non_statics 2>/dev/null || true
        cscli machines add -a 2>/dev/null || true

        # 3e. Install firewall bouncer
        log_info "Installing CrowdSec firewall bouncer..."
        if cmd_exists cs-firewall-bouncer; then
            log_ok "Firewall bouncer already installed"
        else
            apt-get install -y crowdsec-firewall-bouncer-iptables 2>/dev/null || {
                CROWDSC_BOUNCER_VERSION=$(curl -sL "https://api.github.com/repos/crowdsecurity/cs-firewall-bouncer/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
                CROWDSC_BOUNCER_VERSION="${CROWDSC_BOUNCER_VERSION:-v0.0.29}"
                local bouncer_url="https://github.com/crowdsecurity/cs-firewall-bouncer/releases/download/${CROWDSC_BOUNCER_VERSION}/cs-firewall-bouncer.tgz"
                [[ "$REGION" == "CN" ]] && bouncer_url="https://ghfast.top/${bouncer_url}"
                local tmp_dir
                tmp_dir=$(mktemp -d)
                cd "$tmp_dir"
                curl -sL "$bouncer_url" -o bouncer.tgz 2>/dev/null || { log_warn "Bouncer download failed, skipping"; cd /; rm -rf "$tmp_dir"; return 0; }
                tar xzf bouncer.tgz 2>/dev/null || { cd /; rm -rf "$tmp_dir"; return 0; }
                cd /; rm -rf "$tmp_dir"
            }
            log_ok "CrowdSec firewall bouncer installed"
        fi
    else
        log_warn "CrowdSec not available, skipping"
    fi
}

# =============================================================================
# Phase 4 - Hardware Check and Tuning
# =============================================================================

phase4_hardware() {
    log_step "Phase 4 - Hardware Check & Tuning"

    local NEED_SWAP=0

    # 4a. Hardware info collection
    local cpu_cores cpu_model
    cpu_cores=$(nproc)
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' || echo "Unknown")
    log_info "CPU: $cpu_model ($cpu_cores cores)"

    # 4b. RAM check and swap
    log_step "RAM: ${RAM_MB}MB"
    if [[ $RAM_MB -lt 1024 ]]; then
        log_info "RAM < 1GB, swap needed"
        NEED_SWAP=1
    else
        log_info "RAM >= 1GB, swap optional"
        if confirm_yes "Add swap anyway?"; then
            NEED_SWAP=1
        else
            NEED_SWAP=0
            log_ok "Skip swap"
        fi
    fi

    if [[ $NEED_SWAP -eq 1 ]]; then
        # 4c. CPU benchmark
        log_info "Running CPU benchmark (sysbench)..."
        local cpu_events
        cpu_events=$(sysbench cpu run --cpu-max-prime=10000 2>/dev/null | grep "total number of events" | awk '{print $NF}' || echo "0")
        if [[ -n "$cpu_events" && "$cpu_events" -gt 0 ]]; then
            log_info "CPU events: $cpu_events"
            # More than 500 events = strong CPU (rough heuristic for modern VPS)
            if [[ "$cpu_events" -gt 500 ]]; then
                CPU_STRONG=1
                SWAP_TYPE="zram + zstd"
                log_ok "CPU strong, using zram + zstd compression"
            else
                CPU_STRONG=0
                SWAP_TYPE="zram + lz4"
                log_ok "CPU moderate, using zram + lz4 compression"
            fi
        else
            CPU_STRONG=0
            SWAP_TYPE="zram + lz4"
            log_ok "CPU benchmark unavailable, using zram + lz4"
        fi

        # 4d. Set up zram swap
        install_packages zram-tools

        local compression
        [[ $CPU_STRONG -eq 1 ]] && compression="zstd" || compression="lz4"

        # Calculate zram size: 50% of RAM
        local zram_size=$((RAM_MB / 2))
        [[ $zram_size -lt 256 ]] && zram_size=256

        cat > /etc/default/zramswap <<EOF
# VPS Init - zram config
ALGO=$compression
SIZE=${zram_size}M
PRIORITY=100
EOF

        systemctl enable --now zramswap 2>/dev/null || {
            # Manual zram setup if zram-tools doesn't provide service
            modprobe zram 2>/dev/null || true
            local zram_dev="/dev/zram0"
            if [[ ! -b "$zram_dev" ]]; then
                local zram_num
                zram_num=$(cat /sys/class/zram-control/hot_add 2>/dev/null || echo "")
                [[ -z "$zram_num" ]] && zram_dev="" || zram_dev="/dev/zram$zram_num"
            fi
            if [[ -n "$zram_dev" && -b "$zram_dev" ]]; then
                echo "$compression" > /sys/block/$(basename $zram_dev)/comp_algorithm 2>/dev/null || true
                echo "${zram_size}M" > /sys/block/$(basename $zram_dev)/disksize 2>/dev/null || true
                mkswap "$zram_dev" 2>/dev/null || true
                swapon "$zram_dev" -p 100 2>/dev/null || true
            fi
        }
        HAS_SWAP=1
        log_ok "Swap configured: $SWAP_TYPE (${zram_size}MB)"
    fi

    # 4e. Disk check
    log_step "Disk: ${DISK_GB}GB available"
    if [[ $DISK_GB -lt 20 ]]; then
        log_info "Disk < 20GB, applying space-saving measures"

        # Limit journald
        mkdir -p /etc/systemd/journald.conf.d/
        cat > /etc/systemd/journald.conf.d/99-vps-init.conf <<'EOF'
[Journal]
SystemMaxUse=100M
SystemMaxFileSize=50M
MaxRetentionSec=7day
ForwardToSyslog=no
EOF
        systemctl restart systemd-journald 2>/dev/null || true
        log_ok "journald limited to 100M"

        # Configure logrotate to be more aggressive
        cat > /etc/logrotate.d/vps-init <<'EOF'
/var/log/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    maxsize 50M
}
EOF
        log_ok "logrotate configured (weekly, keep 4)"

        # Mount tmpfs for /tmp
        if ! mount | grep -q " /tmp "; then
            local tmpfs_size="256M"
            echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777,size=${tmpfs_size} 0 0" >> /etc/fstab
            mount -a 2>/dev/null || { sed -i '$ d' /etc/fstab; log_warn "tmpfs mount failed"; }
            log_ok "tmpfs mounted for /tmp (${tmpfs_size})"
        fi
    else
        log_ok "Sufficient disk space, no space-saving needed"
    fi

    # 4f. Virtualization protection — block host interference channels
    log_info "Scanning for virtualization interference channels..."
    local blist="/etc/modprobe.d/99-vps-init-blacklist.conf"
    touch "$blist"

    # -- Memory ballooning drivers (host reclaims guest RAM) --
    local balloon_modules=(
        "virtio_balloon"
        "vmw_balloon"
        "xen_balloon"
    )
    local found_balloon=0
    for mod in "${balloon_modules[@]}"; do
        if lsmod 2>/dev/null | grep -q "^${mod}"; then
            log_warn "Found active balloon driver: ${mod}"
            found_balloon=1
        fi
    done

    if [[ $found_balloon -eq 1 ]] || confirm_yes "Block memory balloon drivers?"; then
        for mod in "${balloon_modules[@]}"; do
            if ! grep -q "blacklist ${mod}" "$blist" 2>/dev/null; then
                echo "blacklist ${mod}" >> "$blist"
            fi
            if lsmod 2>/dev/null | grep -q "^${mod}"; then
                modprobe -r "$mod" 2>/dev/null && log_ok "Unloaded: ${mod}" || log_warn "Could not unload ${mod}"
            fi
        done
        log_ok "Balloon drivers blacklisted"
    fi

    # -- Guest agents (host-side RCE / guest command execution) --
    local guest_agents=(
        "qemu-guest-agent:qemu-ga:KVM/QEMU guest agent — allows host to execute commands inside VM"
        "open-vm-tools:vmtoolsd:VMware Tools — host controls guest memory/networking"
        "xe-guest-utilities:xe-daemon:XenServer guest utilities"
        "hv_kvp_daemon:hv_kvp_daemon:Hyper-V key-value pair daemon"
        "hv_vss_daemon:hv_vss_daemon:Hyper-V Volume Shadow Copy daemon"
    )
    local found_agent=0
    for entry in "${guest_agents[@]}"; do
        local pkg="${entry%%:*}"
        local svc
        svc=$(echo "$entry" | cut -d: -f2)
        local desc="${entry##*:}"
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log_warn "Guest agent installed: ${pkg} (${desc})"
            found_agent=1
        fi
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log_warn "Guest agent service running: ${svc}"
            found_agent=1
        fi
    done

    if [[ $found_agent -eq 1 ]] || confirm_yes "Remove guest agents? (blocks host RCE channel)"; then
        for entry in "${guest_agents[@]}"; do
            local pkg="${entry%%:*}"
            if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
                systemctl stop "$(echo "$entry" | cut -d: -f2)" 2>/dev/null || true
                systemctl mask "$(echo "$entry" | cut -d: -f2)" 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg" 2>/dev/null && log_ok "Removed: ${pkg}" || log_warn "Could not purge ${pkg}, service masked"
            fi
        done
        log_ok "Guest agents removed/masked"
    fi

    # -- ACPI memory hotplug (host hot-adds/removes RAM) --
    if grep -q "acpi_memhotplug" /proc/modules 2>/dev/null; then
        log_warn "ACPI memory hotplug detected — host can manipulate guest RAM layout"
        if confirm_yes "Block ACPI memory hotplug?"; then
            if ! grep -q "blacklist acpi_memhotplug" "$blist" 2>/dev/null; then
                echo "blacklist acpi_memhotplug" >> "$blist"
            fi
            modprobe -r acpi_memhotplug 2>/dev/null && log_ok "ACPI memory hotplug blocked" || log_warn "Could not unload acpi_memhotplug"
        fi
    fi

    # -- Kernel NUMA balancing (confuses guest on oversubscribed hosts) --
    local numa_val
    numa_val=$(cat /proc/sys/kernel/numa_balancing 2>/dev/null || echo "0")
    if [[ "$numa_val" != "0" ]]; then
        log_info "Disabling NUMA balancing (prevents host oversubscription inference)"
        cat > /etc/sysctl.d/99-vps-init-numa.conf <<EOF
# VPS Init - Disable NUMA balancing
# Prevents host over-provisioning detection artifacts
kernel.numa_balancing = 0
EOF
        sysctl -w kernel.numa_balancing=0 2>/dev/null || true
        log_ok "NUMA balancing disabled"
    fi

    # -- Transparent hugepage defrag (reduces memory pressure signals) --
    local thp_defrag
    thp_defrag=$(cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || echo "")
    if echo "$thp_defrag" | grep -q "\[always\]"; then
        log_info "Setting THP defrag to madvise (reduces unpredictable memory stalls)"
        echo madvise > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
        echo 'madvise' > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
        cat >> /etc/sysctl.d/99-vps-init-thp.conf <<EOF
# VPS Init - Reduce THP defragmentation pressure
vm.transparent_hugepage/defrag = madvise
EOF
        log_ok "THP defrag set to madvise"
    fi
}

# =============================================================================
# Phase 5 - Speedtest and BBRv3
# =============================================================================

phase5_speedtest_bbr() {
    log_step "Phase 5 - Speedtest & BBRv3"

    # 5a. Install speedtest-cli (Ookla)
    if ! cmd_exists speedtest; then
        log_info "Installing Ookla Speedtest CLI..."
        local st_install_url="https://install.speedtest.net/app/cli/install.deb.sh"
        [[ "$REGION" == "CN" ]] && st_install_url="https://ghfast.top/${st_install_url}"
        curl -sSL "$st_install_url" | bash 2>/dev/null || true
        install_packages speedtest-cli 2>/dev/null || {
            # Direct binary download fallback
            local st_arch="x86_64"
            [[ "$ARCH" == "aarch64" ]] && st_arch="aarch64"
            local st_url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${st_arch}.tgz"
            [[ "$REGION" == "CN" ]] && st_url="https://ghfast.top/${st_url}"
            local tmp_dir
            tmp_dir=$(mktemp -d)
            (
                cd "$tmp_dir"
                curl -sL "$st_url" -o speedtest.tgz 2>/dev/null || { log_warn "Speedtest binary download failed"; exit 1; }
                tar xzf speedtest.tgz 2>/dev/null || exit 1
                mv speedtest /usr/local/bin/speedtest 2>/dev/null || exit 1
            ) || true
            rm -rf "$tmp_dir"
        }
    fi

    # 5b. Run speedtest
    if cmd_exists speedtest; then
        log_info "Running speedtest (this may take a minute)..."
        local st_result
        st_result=$(speedtest --accept-license --accept-gdpr -f json 2>/dev/null || speedtest --accept-license -f json 2>/dev/null || echo "")

        if [[ -n "$st_result" ]]; then
            BANDWIDTH_Mbps=$(echo "$st_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('download',{}).get('bandwidth',0)*8/1000000))" 2>/dev/null || echo "0")
            LATENCY_MS=$(echo "$st_result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(int(d.get('ping',{}).get('latency',0)))" 2>/dev/null || echo "0")
        else
            log_warn "Speedtest failed, using fallback values"
            # Fallback: estimate based on region
            case "$REGION" in
                CN|HK|JP|SG|KR) BANDWIDTH_Mbps=500; LATENCY_MS=10 ;;
                US|CA) BANDWIDTH_Mbps=1000; LATENCY_MS=20 ;;
                DE|NL|FR|GB) BANDWIDTH_Mbps=1000; LATENCY_MS=10 ;;
                *) BANDWIDTH_Mbps=100; LATENCY_MS=50 ;;
            esac
        fi

        log_ok "Speedtest: ${BANDWIDTH_Mbps}Mbps down, ${LATENCY_MS}ms latency"
    else
        log_warn "Speedtest CLI not available, using estimates"
        BANDWIDTH_Mbps=500
        LATENCY_MS=50
    fi

    # 5c. Install XanMod kernel (BBRv3)
    log_info "Installing XanMod kernel (BBRv3)..."
    log_info "Adding XanMod repository..."
    curl -fsSL https://dl.xanmod.org/archive.key 2>/dev/null | gpg --dearmor -o /etc/apt/keyrings/xanmod.gpg 2>/dev/null || true
    echo "deb [signed-by=/etc/apt/keyrings/xanmod.gpg] http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod.list 2>/dev/null || true
    apt-get update -y -qq 2>/dev/null || log_warn "XanMod repo update had issues"

    # Detect correct XanMod package for CPU architecture / x86-64 microarchitecture level
    local xanmod_pkg=""
    if [[ "$ARCH" == "aarch64" ]]; then
        xanmod_pkg="linux-xanmod-arm64"
    elif [[ "$ARCH" == "x86_64" ]]; then
        local flags
        flags=$(grep -o 'flags\s*:.*' /proc/cpuinfo | head -1)
        if echo "$flags" | grep -q "avx512"; then
            xanmod_pkg="linux-xanmod-x64v4"
        elif echo "$flags" | grep -q "avx2"; then
            xanmod_pkg="linux-xanmod-x64v3"
        else
            xanmod_pkg="linux-xanmod-x64v2"
        fi
    fi

    if [[ -n "$xanmod_pkg" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$xanmod_pkg" 2>/dev/null && {
            BBR_INSTALLED=1
            log_ok "XanMod kernel installed: $xanmod_pkg"
        } || log_warn "XanMod kernel install failed — host may not support it, using current kernel"
    else
        log_warn "Unsupported architecture ($ARCH), skipping XanMod kernel"
    fi

    # 5d-5e. Calculate BDP and set TCP parameters
    log_info "Calculating TCP buffer sizes from speedtest..."
    local bdp bdp_kb
    # BDP = bandwidth (bps) * RTT (s) / 8 = bytes
    bdp=$(echo "$BANDWIDTH_Mbps * 1000000 * $LATENCY_MS / 1000 / 8" | bc -l 2>/dev/null || echo "1048576")
    bdp=$(printf "%.0f" "$bdp" 2>/dev/null || echo "1048576")
    bdp_kb=$((bdp / 1024))
    [[ $bdp_kb -lt 256 ]] && bdp_kb=256
    [[ $bdp_kb -gt 65536 ]] && bdp_kb=65536

    local tcp_max=$((bdp_kb * 2))
    [[ $tcp_max -gt 131072 ]] && tcp_max=131072

    log_info "BDP: ${bdp_kb}KB, setting TCP buffers (max: ${tcp_max}KB)"

    # Apply TCP sysctl settings
    cat > /etc/sysctl.d/99-vps-tcp.conf <<EOF
# VPS Init - TCP BBRv3 optimization
# BDP-based tuning: ${BANDWIDTH_Mbps}Mbps x ${LATENCY_MS}ms

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Buffer sizes derived from BDP
net.core.rmem_max = $((tcp_max * 1024))
net.core.wmem_max = $((tcp_max * 1024))
net.ipv4.tcp_rmem = 4096 $((bdp_kb * 1024)) $((tcp_max * 1024))
net.ipv4.tcp_wmem = 4096 $((bdp_kb * 1024)) $((tcp_max * 1024))

# TCP optimization
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0

# General
fs.file-max = 2097152
vm.swappiness = 10
EOF

    sysctl --system > /dev/null 2>&1
    log_ok "TCP sysctl parameters applied (BBRv3, fq, buffers: ${bdp_kb}KB)"
}

# =============================================================================
# Phase 6 - Cloudflare Tunnel
# =============================================================================

phase6_cloudflare_tunnel() {
    log_step "Phase 6 - Cloudflare Tunnel"

    if ! confirm_yes "Install Cloudflare Tunnel?"; then
        log_info "Skipping Cloudflare Tunnel"
        return 0
    fi

    # 6a. Download cloudflared binary
    log_info "Downloading cloudflared..."
    local cf_arch="amd64"
    case "$ARCH" in
        x86_64)     cf_arch="amd64" ;;
        aarch64)    cf_arch="arm64" ;;
        armv7l|armhf) cf_arch="arm" ;;
        i386|i686)  cf_arch="386" ;;
    esac

    local cf_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
    [[ "$REGION" == "CN" ]] && cf_url="https://ghfast.top/${cf_url}"

    curl -sL "$cf_url" -o /usr/local/bin/cloudflared 2>/dev/null || {
        log_error "Failed to download cloudflared"
        return 1
    }
    chmod +x /usr/local/bin/cloudflared
    log_ok "cloudflared downloaded"

    # 6b. Verify
    if ! /usr/local/bin/cloudflared version &>/dev/null; then
        log_error "cloudflared binary not working"
        return 1
    fi

    # 6c. Interactive: Input tunnel token
    log_info "You need a Cloudflare Tunnel token."
    log_info "Create one in Cloudflare Dashboard: Zero Trust > Access > Tunnets"
    local tunnel_token=""
    read -rp "$(echo -e "${YELLOW}Paste your Tunnel Token (or leave empty to skip): ${PLAIN}")" tunnel_token

    if [[ -z "$tunnel_token" ]]; then
        log_info "Skipping tunnel registration"
        CLOUDFLARED_INSTALLED=1
        return 0
    fi

    # 6d. Register as systemd service
    /usr/local/bin/cloudflared service install "$tunnel_token" 2>&1 || {
        # Manual systemd setup
        cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel run --token ${tunnel_token}
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    }

    # 6e. Start and verify
    systemctl enable --now cloudflared 2>/dev/null || systemctl enable --now cloudflared.service 2>/dev/null || log_warn "Could not start cloudflared service"

    # Give it a moment to connect
    sleep 3
    if systemctl is-active --quiet cloudflared 2>/dev/null; then
        CLOUDFLARED_INSTALLED=1
        log_ok "Cloudflare Tunnel service running"
    else
        log_warn "Cloudflare Tunnel service may not be running, check: systemctl status cloudflared"
        CLOUDFLARED_INSTALLED=1
    fi
}

# =============================================================================
# Phase 7 - Summary and Reboot
# =============================================================================

phase7_summary() {
    log_step "Phase 7 - Summary"

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))
    local bbr_status="Not installed"
    local swap_status="No"
    local crowdsec_status="Not installed"

    [[ $BBR_INSTALLED -eq 1 ]] && bbr_status="Installed (active after reboot)"
    [[ $HAS_SWAP -eq 1 ]] && swap_status="Yes ($SWAP_TYPE)"
    cmd_exists crowdsec && crowdsec_status="Installed"

    # Collect all results and print summary
    local summary
    summary=$(cat <<EOF
=============================================================
  VPS Init Complete - Setup Report
=============================================================
  Time:           $(date '+%Y-%m-%d %H:%M:%S')
  Duration:       ${elapsed_min}m ${elapsed_sec}s
  Hostname:       $HOSTNAME

  -- Environment --
  OS:             ${OS_NAME} ${OS_VERSION} (${OS_CODENAME})
  Architecture:   $ARCH
  Region:         $REGION
  Timezone:       $TIMEZONE
  Mirror:         $BEST_MIRROR

  -- System --
  RAM:            ${RAM_MB}MB
  Disk:           ${DISK_GB}GB free
  Swap:           $swap_status
  Bandwidth:      ${BANDWIDTH_Mbps}Mbps
  Latency:        ${LATENCY_MS}ms

  -- Security --
  SSH Port:       $SSH_PORT
  SSH User:       $USERNAME
  UFW:            Active (deny incoming)
  fail2ban:       Active
  CrowdSec:       $crowdsec_status

  -- Network --
  TCP CC:         bbr
  Qdisc:          fq
  TCP Buffers:    BDP-optimized
  BBRv3:          $bbr_status

  -- Optional --
  Cloudflare:     $([ $CLOUDFLARED_INSTALLED -eq 1 ] && echo "Installed" || echo "Not installed")

=============================================================
  Connect: ssh -p $SSH_PORT $USERNAME@<SERVER_IP>
=============================================================
EOF
)

    echo ""
    echo -e "${GREEN}${BOLD}$summary${PLAIN}"
    echo ""

    # Save report
    echo "$summary" > "$REPORT_FILE"
    log_ok "Report saved to $REPORT_FILE"
}

phase7_reboot() {
    log_step "Reboot"

    echo -e "${YELLOW}${BOLD}System will reboot in 10 seconds...${PLAIN}"
    echo -e "${YELLOW}Press Ctrl+C to cancel reboot${PLAIN}"
    echo ""

    for ((i=10; i>=1; i--)); do
        echo -ne "\r${YELLOW}Rebooting in $i seconds... ${PLAIN}"
        sleep 1
    done
    echo ""

    log_info "Rebooting now..."
    reboot
}

# =============================================================================
# Main Flow
# =============================================================================

main() {
    START_TIME=$(date +%s)

    show_banner
    check_root

    phase1_detect_env
    phase2_base_init
    phase3_security
    phase4_hardware
    phase5_speedtest_bbr
    phase6_cloudflare_tunnel
    phase7_summary
    phase7_reboot
}

main "$@"
