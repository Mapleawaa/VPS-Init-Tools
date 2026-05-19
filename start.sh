#!/bin/bash
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PLAIN='\033[0m'
readonly BOLD='\033[1m'

readonly REPO_BASE="https://raw.githubusercontent.com/Mapleawaa/VPS-Init-Tools/main"
readonly SCRIPTS=(
    "init-cn.sh:快速配置 — SSH加固 + UFW + Fail2Ban + ZSH + 监控 (仅国内)"
    "init-pure-debian.sh:完整功能 — 双语菜单 + 可选组件 (ZSH/Docker/K3s/面板/WAF)"
    "vps-init.sh:全自动流程 — Region检测 + BBRv3 + CrowdSec + Cloudflare Tunnel"
)

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Must run as root${PLAIN}"
        exit 1
    fi
}

show_banner() {
    echo ""
    echo -e "${BLUE}${BOLD}  ╔══════════════════════════════════════════════════════╗${PLAIN}"
    echo -e "${BLUE}${BOLD}  ║              VPS Init Tools Launcher                ║${PLAIN}"
    echo -e "${BLUE}${BOLD}  ║         https://github.com/Mapleawaa/VPS-Init-Tools  ║${PLAIN}"
    echo -e "${BLUE}${BOLD}  ╚══════════════════════════════════════════════════════╝${PLAIN}"
    echo ""
}

show_menu() {
    echo -e "${CYAN}${BOLD}Select an initialization script:${PLAIN}"
    echo ""
    for i in "${!SCRIPTS[@]}"; do
        local num=$((i + 1))
        local name="${SCRIPTS[$i]%%:*}"
        local desc="${SCRIPTS[$i]#*:}"
        echo -e "  ${GREEN}${BOLD}[${num}]${PLAIN} ${CYAN}${name}${PLAIN}"
        echo -e "       ${desc}"
        echo ""
    done
    echo -e "  ${RED}${BOLD}[q]${PLAIN} Quit"
    echo ""
}

run_script() {
    local script_name="$1"

    if [[ -f "./$script_name" ]]; then
        echo -e "${GREEN}Running local ${script_name}...${PLAIN}"
        exec bash "./$script_name"
    else
        local url="${REPO_BASE}/${script_name}"
        echo -e "${GREEN}Downloading ${script_name} from ${url} ...${PLAIN}"
        bash <(curl -fsSL "$url") || {
            echo -e "${RED}Failed to download or execute ${script_name}${PLAIN}"
            exit 1
        }
    fi
}

main() {
    show_banner
    check_root
    show_menu

    local choice
    read -rp "$(echo -e "${YELLOW}Enter your choice [1-3] or q: ${PLAIN}")" choice

    case "$choice" in
        1) run_script "init-cn.sh" ;;
        2) run_script "init-pure-debian.sh" ;;
        3) run_script "vps-init.sh" ;;
        q|Q) echo -e "${YELLOW}Goodbye.${PLAIN}"; exit 0 ;;
        *) echo -e "${RED}Invalid choice.${PLAIN}"; exit 1 ;;
    esac
}

main "$@"
