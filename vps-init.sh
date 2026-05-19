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

# Debian mirror regions keyed by country code
# Format: region_name|mirror1,url1|mirror2,url2|...
# First entry is always the official Debian mirror for that region

declare -A REGION_MIRRORS
REGION_MIRRORS["Global"]="Debian Official|http://deb.debian.org/debian/"

REGION_MIRRORS["JP"]="Debian Official|http://ftp.jp.debian.org/debian/|RIKEN|http://ftp.riken.jp/Linux/debian/debian/|JAIST|http://ftp.jaist.ac.jp/pub/Linux/Debian/debian/|Tsukuba Univ|http://ftp.tsukuba.wide.ad.jp/Linux/debian/|Yamagata Univ|http://ftp.yz.yamagata-u.ac.jp/pub/linux/debian/|Tokyo Tech|http://ftp.titech.ac.jp/Linux/debian/|IIJ|http://ftp.iij.ad.jp/pub/linux/debian/debian/|xTom JP|http://mirror.xtom.jp/debian/"

REGION_MIRRORS["SG"]="Debian Official|http://ftp.sg.debian.org/debian/|NUS|http://mirror.nus.edu.sg/debian/|SG.GS|http://mirror.sg.gs/debian/"

REGION_MIRRORS["KR"]="Debian Official|http://ftp.kr.debian.org/debian/|KAIST|http://ftp.kaist.ac.kr/debian/|KREONET|http://ftp.kreonet.net/debian/|LANET|http://ftp.lanet.kr/debian/"

REGION_MIRRORS["HK"]="Debian Official|http://ftp.hk.debian.org/debian/|xTom|http://mirror.xtom.com.hk/debian/|HKIX|http://ftp.hk.debian.org/debian/"

REGION_MIRRORS["US"]="Debian Official|http://ftp.us.debian.org/debian/|OSUOSL|http://debian.osuosl.org/debian/|MIT|http://debian.csail.mit.edu/debian/|Princeton|http://mirror.math.princeton.edu/pub/debian/|Kernel.org|http://mirrors.kernel.org/debian/|Leaseweb US|http://mirror.us.leaseweb.net/debian/|Steadfast|http://mirror.steadfast.net/debian/"

REGION_MIRRORS["DE"]="Debian Official|http://ftp.de.debian.org/debian/|FAU Erlangen|http://ftp.fau.de/debian/|TU Dresden|http://ftp.tu-dresden.de/debian/|RWTH Aachen|http://ftp.halifax.rwth-aachen.de/debian/|NetCologne|http://mirror.netcologne.de/debian/|DFN|http://ftp.hosteurope.de/mirror/debian.org/"

REGION_MIRRORS["NL"]="Debian Official|http://ftp.nl.debian.org/debian/|Leaseweb NL|http://mirror.nl.leaseweb.net/debian/|Worldstream|http://mirror.worldstream.nl/debian/|NForce|http://mirror.nforce.com/pub/linux/debian/|Univ of Twente|http://ftp.snt.utwente.nl/debian/"

REGION_MIRRORS["GB"]="Debian Official|http://ftp.uk.debian.org/debian/|MirrorService|http://www.mirrorservice.org/sites/ftp.debian.org/debian/|RapidSwitch|http://mirror.ox.ac.uk/sites/ftp.debian.org/debian/|Bytemark|http://mirror.bytemark.co.uk/debian/"

REGION_MIRRORS["FR"]="Debian Official|http://ftp.fr.debian.org/debian/|CRIFO|http://ftp.crifo.org/debian/|Univ Lorraine|http://miroir.univ-lorraine.fr/debian/"

REGION_MIRRORS["SE"]="Debian Official|http://ftp.se.debian.org/debian/|Umea Univ|http://ftp.acc.umu.se/debian/"

REGION_MIRRORS["CH"]="ETH Zurich|http://debian.ethz.ch/debian/"

REGION_MIRRORS["CA"]="Debian Official|http://ftp.ca.debian.org/debian/"

REGION_MIRRORS["AU"]="Debian Official|http://ftp.au.debian.org/debian/"

# Country code -> region mapping for servers not in specific list
declare -A COUNTRY_TO_REGION
COUNTRY_TO_REGION["JP"]="JP"
COUNTRY_TO_REGION["SG"]="SG"
COUNTRY_TO_REGION["KR"]="KR"
COUNTRY_TO_REGION["HK"]="HK"
COUNTRY_TO_REGION["US"]="US"
COUNTRY_TO_REGION["DE"]="DE"
COUNTRY_TO_REGION["NL"]="NL"
COUNTRY_TO_REGION["GB"]="GB"
COUNTRY_TO_REGION["UK"]="GB"
COUNTRY_TO_REGION["FR"]="FR"
COUNTRY_TO_REGION["SE"]="SE"
COUNTRY_TO_REGION["CH"]="CH"
COUNTRY_TO_REGION["CA"]="CA"
COUNTRY_TO_REGION["AU"]="AU"
COUNTRY_TO_REGION["IT"]="DE"
COUNTRY_TO_REGION["ES"]="FR"
COUNTRY_TO_REGION["NO"]="SE"
COUNTRY_TO_REGION["DK"]="SE"
COUNTRY_TO_REGION["FI"]="SE"
COUNTRY_TO_REGION["PL"]="DE"
COUNTRY_TO_REGION["AT"]="DE"
COUNTRY_TO_REGION["BE"]="NL"
COUNTRY_TO_REGION["IE"]="GB"
COUNTRY_TO_REGION["PT"]="FR"
COUNTRY_TO_REGION["RU"]="DE"
COUNTRY_TO_REGION["IN"]="SG"
COUNTRY_TO_REGION["ID"]="SG"
COUNTRY_TO_REGION["MY"]="SG"
COUNTRY_TO_REGION["TH"]="SG"
COUNTRY_TO_REGION["VN"]="SG"
COUNTRY_TO_REGION["PH"]="SG"
COUNTRY_TO_REGION["TW"]="HK"
COUNTRY_TO_REGION["MO"]="HK"
COUNTRY_TO_REGION["NZ"]="AU"
COUNTRY_TO_REGION["MX"]="US"
COUNTRY_TO_REGION["BR"]="US"
COUNTRY_TO_REGION["AR"]="US"

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

# Speedtest a single mirror by measuring download time of a test file
mirror_speed() {
    local url="$1"
    local test_url="${url}dists/stable/Release"
    local start_time end_time elapsed

    start_time=$(date +%s.%N)
    curl -s --connect-timeout 5 --max-time 15 -o /dev/null "$test_url" 2>/dev/null || {
        echo "999"
        return
    }
    end_time=$(date +%s.%N)
    elapsed=$(echo "$end_time - $start_time" | awk '{printf "%.3f", $1}')
    echo "$elapsed"
}

# Find best mirror for a given region by speedtesting all mirrors
find_best_mirror() {
    local country="$1"
    local region_key="${COUNTRY_TO_REGION[$country]:-Global}"
    local mirror_data="${REGION_MIRRORS[$region_key]:-${REGION_MIRRORS[Global]}}"

    log_info "Testing mirrors for region: $region_key..."

    local best_url=""
    local best_time=999
    local best_name=""
    # Mirror data format: name1|url1|name2|url2|...
    local -a parts=()
    local saved_ifs="$IFS"
    IFS='|' read -ra parts <<< "$mirror_data"
    IFS="$saved_ifs"
    local i=0
    while [[ $i -lt ${#parts[@]} ]]; do
        local name="${parts[$i]}"
        local url="${parts[$i+1]:-}"
        if [[ -n "$url" ]]; then
            echo -ne "${YELLOW}  Testing $name...${PLAIN}   \r"
            local speed
            speed=$(mirror_speed "$url")
            if [[ "$(echo "$speed < $best_time" | bc -l 2>/dev/null || echo 0)" == "1" ]]; then
                best_time="$speed"
                best_url="$url"
                best_name="$name"
            fi
            echo -ne "  ${name}: ${speed}s                         \n"
        fi
        i=$((i + 2))
    done

    if [[ -n "$best_url" ]]; then
        BEST_MIRROR="$best_url"
        log_ok "Best mirror: $best_name ($BEST_MIRROR) - ${best_time}s"
    else
        log_warn "All mirrors failed, using fallback"
        BEST_MIRROR="http://deb.debian.org/debian/"
    fi
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
    find_best_mirror "$REGION"

    local release_name="${OS_CODENAME:-bookworm}"

    if [[ "$OS_NAME" == "ubuntu" ]]; then
        # Ubuntu format: security is part of the main archive
        cat > /etc/apt/sources.list <<EOF
deb $BEST_MIRROR $release_name main restricted universe multiverse
deb $BEST_MIRROR $release_name-updates main restricted universe multiverse
deb $BEST_MIRROR $release_name-backports main restricted universe multiverse
deb $BEST_MIRROR $release_name-security main restricted universe multiverse
EOF
    else
        # Debian format: separate security archive
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
        apt-transport-https software-properties-common \
        net-tools dnsutils htop tmux vim unzip jq \
        bc sysbench python3 ufw fail2ban openssh-server

    log_ok "Base tools installed"

    # 2d. Import SSH public key
    log_step "SSH Configuration"
    read -rp "$(echo -e "${YELLOW}Username: ${PLAIN}")" USERNAME
    USERNAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]' | xargs)
    [[ -z "$USERNAME" ]] && { log_error "Username cannot be empty"; exit 1; }

    read -rp "$(echo -e "${YELLOW}SSH Public Key (required): ${PLAIN}")" USER_PUB_KEY
    [[ -z "$USER_PUB_KEY" ]] && { log_error "SSH key required to prevent lockout"; exit 1; }

    read -rp "$(echo -e "${YELLOW}SSH Port (default 2077): ${PLAIN}")" SSH_PORT
    SSH_PORT="${SSH_PORT:-2077}"

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

    # SSH key
    local home="/home/${USERNAME}"
    mkdir -p "${home}/.ssh"
    echo "$USER_PUB_KEY" > "${home}/.ssh/authorized_keys"
    chmod 700 "${home}/.ssh" && chmod 600 "${home}/.ssh/authorized_keys"
    chown -R "${USERNAME}:${USERNAME}" "${home}/.ssh"
    log_ok "SSH key added for $USERNAME"

    # 2e. Harden SSH config
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

    # Ensure SSH service is running
    systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
    log_ok "SSH hardened (port: $SSH_PORT)"

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

    # 5c. Install BBRv3 kernel via external script
    log_info "Installing BBRv3 kernel (XanMod)..."
    local tcp_tune_url="https://raw.githubusercontent.com/Eric86777/vps-tcp-tune/main/net-tcp-tune.sh"
    [[ "$REGION" == "CN" ]] && tcp_tune_url="https://ghfast.top/${tcp_tune_url}"

    local tcp_script="/tmp/net-tcp-tune.sh"
    if curl -fsSL "$tcp_tune_url" -o "$tcp_script" 2>/dev/null; then
        chmod +x "$tcp_script"
        # Run function 1 (install XanMod kernel + BBRv3) non-interactively
        # The script reads user input from stdin for menu selection
        log_info "Running kernel installation (function 1)..."
        echo "1" | bash "$tcp_script" 2>&1 || log_warn "Kernel install had issues"

        # Check if XanMod kernel is installed
        if dpkg -l | grep -q "linux-image.*xanmod" 2>/dev/null; then
            BBR_INSTALLED=1
            log_ok "XanMod kernel (BBRv3) installed"
        else
            # Manual XanMod installation as fallback
            log_info "Attempting manual XanMod kernel install..."
            curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor -o /etc/apt/keyrings/xanmod.gpg 2>/dev/null || true
            echo "deb [signed-by=/etc/apt/keyrings/xanmod.gpg] http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod.list 2>/dev/null || true
            apt-get update -y -qq 2>/dev/null || true

            # Detect x64v level
            local xanmod_pkg="linux-xanmod-x64v3"
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

            DEBIAN_FRONTEND=noninteractive apt-get install -y "$xanmod_pkg" 2>/dev/null && {
                BBR_INSTALLED=1
                log_ok "XanMod kernel installed manually: $xanmod_pkg"
            } || log_warn "XanMod kernel install failed, will use current kernel"
        fi
    else
        log_warn "Failed to download tcp-tune script, attempting direct XanMod setup"
        curl -fsSL https://dl.xanmod.org/archive.key | gpg --dearmor -o /etc/apt/keyrings/xanmod.gpg 2>/dev/null || true
        echo "deb [signed-by=/etc/apt/keyrings/xanmod.gpg] http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod.list 2>/dev/null || true
        apt-get update -y -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y linux-xanmod-x64v3 2>/dev/null && {
            BBR_INSTALLED=1
            log_ok "XanMod kernel installed"
        } || log_warn "Could not install BBRv3 kernel"
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
