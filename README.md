# VPS Init — 服务器初始化脚本集

一键将纯净 Debian/Ubuntu VPS 配置为开箱即用的生产环境。

## 一键启动

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mapleawaa/VPS-Init-Tools/main/start.sh)
```

选择菜单中的脚本即可开始初始化，无需手动下载。

## 脚本对比

| | `init-pure-debian.sh` | `init-cn.sh` | `vps-init.sh` |
|---|---|---|---|
| **定位** | 纯净 Debian，功能全面 | 快速配置，偏向简洁 | 全自动流程化初始化 |
| **系统** | Debian (推荐) | Debian / Ubuntu | Debian / Ubuntu |
| **双语** | 中文/英文自动切换 | 仅中文 | 仅中文 |
| **可选组件** | ZSH / Docker / K3s / 面板 / WAF | ZSH / 监控工具 | CrowdSec / Cloudflare Tunnel |
| **交互方式** | 编号多选菜单 | 逐步 y/n | 按阶段自动+交互 |
| **Region 检测** | 手动选择 | 手动选择 | 自动 (Cloudflare CGI) |
| **BBR** | 基础 sysctl | 无 | XanMod BBRv3 内核 |
| **换源策略** | 手动选国内/海外 | 手动选国内/海外 | 国内 linuxmirrors.cn，海外按国家码测速选最优 |

---

## vps-init.sh

全自动化 VPS 初始化脚本，覆盖环境检测→换源→安全加固→硬件调优→BBRv3→Cloudflare Tunnel→重启的完整流程。

### 架构概览

```
┌──────────────────────────────────────────────────────────┐
│  Phase 1  环境检测 (全自动)                                │
│    OS/架构 → Cloudflare CGI 检测 Region → 硬件信息收集      │
├──────────────────────────────────────────────────────────┤
│  Phase 2  基础初始化                                       │
│    CN → linuxmirrors.cn 交互选源 / 海外 → 测速选最优镜像    │
│    → apt update/upgrade → 基础工具 → SSH 公钥 + 加固       │
│    → 设置主机名 + 时区 (按 Region 自动匹配)                 │
├──────────────────────────────────────────────────────────┤
│  Phase 3  安全加固                                        │
│    UFW (default deny) → fail2ban → CrowdSec + 场景 + 防火墙弹窗 │
├──────────────────────────────────────────────────────────┤
│  Phase 4  硬件检测 & 调优                                  │
│    RAM < 1GB → sysbench CPU 基准 → zram (zstd/lz4)       │
│    Disk < 20GB → 限制 journald + logrotate + tmpfs        │
├──────────────────────────────────────────────────────────┤
│  Phase 5  Speedtest & BBRv3                               │
│    speedtest-cli 测速 (记录带宽/RTT) → XanMod BBRv3 内核   │
│    BDP 计算 → TCP 缓冲区调优 → fq qdisc + bbr CC          │
├──────────────────────────────────────────────────────────┤
│  Phase 6  Cloudflare Tunnel (可选)                        │
│    下载 cloudflared → 交互输入 Token → systemd 服务       │
├──────────────────────────────────────────────────────────┤
│  Phase 7  总结 & 重启                                     │
│    输出完整报告到 /root/setup-report.log → 10s 倒计时重启  │
└──────────────────────────────────────────────────────────┘
```

### 核心特性

| 特性 | 说明 |
|------|------|
| **Region 自动检测** | 请求 `https://www.dyson.cn/cdn-cgi/trace`，解析 `loc=` 字段自动区分国内/海外 |
| **智能换源 (国内)** | 调用 `linuxmirrors.cn` 交互选源，失败自动回退阿里云 |
| **智能换源 (海外)** | 按国家码匹配镜像区域，内置 14 个地区的 Debian 镜像列表，自动测速选最优 |
| **CPU 自适应 Swap** | sysbench 基准测试，CPU 强用 zstd 压缩，弱用 lz4，zram 大小 = RAM/2 |
| **BDP 驱动 TCP 调优** | 根据 speedtest 实测带宽和 RTT 计算 BDP，动态设置 `rmem/wmem` |
| **BBRv3** | 使用 [Eric86777/vps-tcp-tune](https://github.com/Eric86777/vps-tcp-tune) 安装 XanMod 内核 |
| **三层安全防御** | UFW (默认拒绝入站) + fail2ban + CrowdSec (带 SSH/HTTP 攻击场景) |
| **磁盘自适应** | < 20GB 自动限制 journald 日志 (100M)、logrotate (weekly)、挂载 tmpfs |

### 海外镜像区域

内置以下地区的 Debian 镜像源列表，自动测速选最优：

| 区域 | 国家码 | 镜像数 |
|------|--------|--------|
| 日本 | JP | 8 |
| 新加坡 | SG | 3 |
| 韩国 | KR | 4 |
| 香港 | HK | 3 |
| 美国 | US | 7 |
| 德国 | DE | 6 |
| 荷兰 | NL | 5 |
| 英国 | GB | 4 |
| 法国 | FR | 3 |
| 瑞典 | SE | 2 |
| 瑞士 | CH | 1 |
| 加拿大 | CA | 1 |
| 澳大利亚 | AU | 1 |

未匹配的国家自动映射到最近区域（如 IT→DE, BR→US, IN→SG 等）。

### 使用方法

```bash
# 上传到服务器
scp vps-init.sh root@your-server-ip:/root/

# 运行
chmod +x vps-init.sh
./vps-init.sh
```

---

## init-pure-debian.sh

完整功能版初始化脚本，详见上方文档。

### 架构概览

```
┌─────────────────────────────────────────────────────┐
│  Phase 0  启动                                      │
│    横幅 → Root 检查 → 中文显示检测 (设置双语模式)      │
├─────────────────────────────────────────────────────┤
│  Phase 1  区域 & 环境检测 (全自动，无需交互)           │
│    区域选择 → OS/Arch/内核 → 磁盘 → 网络 → 命令 → locale │
├─────────────────────────────────────────────────────┤
│  Phase 2  备份 & APT                                 │
│    文件备份 → 镜像源配置 → apt update/upgrade → 基础工具 │
├─────────────────────────────────────────────────────┤
│  Phase 3  用户 & SSH                                 │
│    创建用户 → sudo NOPASSWD → SSH 公钥 → sshd 加固     │
├─────────────────────────────────────────────────────┤
│  Phase 4  安全                                      │
│    UFW 防火墙 → Fail2Ban                            │
├─────────────────────────────────────────────────────┤
│  Phase 5  可选组件 (编号多选菜单)                      │
│    ZSH / Docker / K3s / 监控 / 面板 / WAF            │
├─────────────────────────────────────────────────────┤
│  Phase 6  系统优化 & 收尾                             │
│    时区 → vim → limits → sysctl → 摘要 → 重启 SSH     │
└─────────────────────────────────────────────────────┘
```

### 各 Phase 详细说明

#### Phase 0 — 启动 & 显示检测

- **Root 权限检查**：非 Root 直接退出
- **中文显示检测**：脚本启动后首先询问用户能否正常看到中文
  - 用户确认 → `CAN_DISPLAY_CN=1`，后续所有交互以中文输出
  - 用户看到乱码 → `CAN_DISPLAY_CN=0`，切换为全英文输出
  - **不修改系统 locale**，不写 `/etc/default/locale`，不影响 TTY 默认语言

#### Phase 1 — 区域 & 环境检测

全自动执行，无需用户交互。仅做信息展示和前置校验：

| 检查项 | 行为 |
|--------|------|
| 区域选择 | 用户选国内/海外，影响后续镜像源 |
| OS / Arch / 内核 | 展示系统信息，非 Debian 给出警告 |
| 系统运行时间 | <300s 提示疑似全新安装 |
| 已有普通用户 | 列出 UID>=1000 的用户 |
| 磁盘空间 | <2GB 直接退出 |
| 网络连通性 | curl 测试 deb.debian.org |
| 基础命令 | 检查 awk/sed/grep/curl/dpkg/apt-get/systemctl |
| Locale | 仅展示当前 LANG 和已生成的 locale，**不做任何修改** |

#### Phase 2 — 备份 & APT

**备份策略**：修改前自动备份，带时间戳目录：

```
/root/init-backup-20260327_153000/
└── etc/
    ├── ssh/sshd_config
    └── fail2ban/jail.local
```

**APT 配置**：

- 国内模式：切换为阿里云镜像源（`mirrors.aliyun.com`），自动适配 Debian 版本代号
- 海外模式：保持默认官方源

**安装基础工具包**：

| 类别 | 包列表 |
|------|--------|
| 网络工具 | curl wget git |
| 系统管理 | sudo ca-certificates gnupg lsb-release apt-transport-https software-properties-common |
| 运维工具 | net-tools dnsutils htop tmux vim unzip jq |
| 安全工具 | ufw fail2ban |

所有包安装前检查是否已存在，已安装的自动跳过。

#### Phase 3 — 用户 & SSH

**用户创建流程**：

```
输入用户名 → 自动转小写 → 格式校验 → 保留名检查 → 重复检查
    ↓
设置密码 (回车=随机20位) → 选择 Shell (bash/zsh) → 创建用户
    ↓
sudo 权限 → NOPASSWD 组 → sudoers.d 写入
```

- 用户名格式：`^[a-z_][a-z0-9_-]*$`
- 保留名：root / admin / debian
- 密码：支持手动输入或 `/dev/urandom` 随机生成 20 位
- 用户已存在时自动复用，跳过创建步骤

**SSH 加固**：

通过 `_sshd_set()` 函数安全修改 `sshd_config`，每个参数先 sed 替换已有行，不存在则追加：

| 参数 | 值 | 说明 |
|------|-----|------|
| `Port` | 用户指定 (默认 2077) | 高位端口避免扫描 |
| `PermitRootLogin` | `no` | 禁止 Root 登录 |
| `PasswordAuthentication` | `no` | 禁止密码登录 |
| `PubkeyAuthentication` | `yes` | 仅允许密钥 |
| `PermitEmptyPasswords` | `no` | 禁止空密码 |
| `MaxAuthTries` | `3` | 限制认证尝试次数 |
| `ClientAliveInterval` | `300` | 5 分钟 Keep-Alive |
| `ClientAliveCountMax` | `2` | 最多 2 次未响应断开 |
| `X11Forwarding` | `no` | 禁用 X11 转发 |

公钥必填且做格式校验，为空直接退出防止锁死。

#### Phase 4 — 安全

**UFW 防火墙**：

```
默认策略: deny incoming / allow outgoing
预设规则: SSH(自定义端口) / HTTP(80) / HTTPS(443)
支持追加: 用户可输入额外端口 (如 8080/tcp)
```

**Fail2Ban**：

| 参数 | 值 |
|------|-----|
| 全局封禁时长 | 1 小时 |
| 全局重试窗口 | 10 分钟 |
| 全局最大重试 | 5 次 |
| SSH 监控端口 | 与 SSH_PORT 一致 |
| SSH 最大重试 | 3 次 |
| banaction | ufw |

#### Phase 5 — 可选组件

一次性展示菜单，用户输入编号空格分隔即可多选：

```
── 可多选，输入编号用空格分隔，回车跳过全部 ──

  [1] ZSH + Oh My Zsh
  [2] Docker
  [3] K3s (轻量 Kubernetes)
  [4] 监控工具 (btop / fastfetch)
  [5] 运维面板 (1Panel / 宝塔 / CasaOS)
  [6] WAF (SafeLine 雷池 / BunkerWeb)

输入编号 (空格分隔，回车跳过): 1 2 4
```

**[1] ZSH + Oh My Zsh**

- 安装 zsh → chsh 切换默认 Shell
- Oh My Zsh 无人值守安装（国内走 `ohmy.schue.we.cn` 镜像）
- 插件：zsh-autosuggestions + zsh-syntax-highlighting（国内走 ghfast.top）
- 主题：ys

**[2] Docker**

- 官方源安装（国内走阿里云镜像 `mirrors.aliyun.com/docker-ce`）
- 组件：docker-ce, docker-ce-cli, containerd.io, buildx-plugin, compose-plugin
- 用户自动加入 docker 组

**[3] K3s**

- 国内走 Rancher 中文镜像 `rancher-mirror.rancher.cn`，设置 `INSTALL_K3S_MIRROR=cn`
- 默认禁用 traefik（`--disable=traefik`），避免端口冲突
- 启用 K3s 服务，输出配置文件路径

**[4] 监控工具**

- btop：系统资源监控
- fastfetch（优先）或 neofetch：系统信息，自动写入 shell rc

**[5] 运维面板**（子菜单选择）

| 面板 | 安装源 | 特点 |
|------|--------|------|
| **1Panel** | fit2cloud 官方脚本 | 现代化开源面板，Docker 管理 |
| **宝塔面板** | bt.cn 官方脚本 | 经典运维面板，插件生态丰富 |
| **CasaOS** | get.casaos.io | 轻量家庭云，适合 NAS 场景 |

**[6] WAF**（子菜单选择）

| WAF | 安装源 | 依赖 | 管理界面 |
|-----|--------|------|----------|
| **SafeLine (雷池)** | chaitin.cn 官方脚本 | Docker | `http://<IP>:9443` |
| **BunkerWeb** | get.bunkerweb.io | 无 | `http://<IP>:8080` |

#### Phase 6 — 系统优化 & 收尾

| 优化项 | 配置文件 | 内容 |
|--------|----------|------|
| 时区 | systemd | 可选修改，预设 5 个常用时区 + 手动输入 |
| vim | `/etc/vim/vimrc.local` | 行号、缩进、UTF-8、搜索高亮 |
| 文件描述符 | `/etc/security/limits.conf` | nofile/nproc 均为 65535 |
| 内核参数 | `/etc/sysctl.d/99-custom.conf` | TCP 优化、反向路径过滤、禁用 ICMP 重定向等 |

最后输出配置摘要（用户名、密码、SSH 端口），提示用户在**新终端**测试连接后再重启 SSH。

---

### 使用方法

```bash
# 上传到服务器
scp init-pure-debian.sh root@your-server-ip:/root/

# 运行
chmod +x init-pure-debian.sh
./init-pure-debian.sh
```

### 交互流程示例

```
═══════════════════════════════════════════════════════
      Debian Server Init v1.1.0
═══════════════════════════════════════════════════════

  请确认：你能正常看到这行中文吗？
  如果显示正常请输入 Y，如果看到乱码请输入 N

中文显示正常 [y/N]: y
[INFO]  显示模式: 中文

── 区域选择 ──

  1. 海外 (默认源)
  2. 国内 (镜像源加速)
请选择 [1-2]: 2
[ OK ]  已选择: 国内模式

── 环境检测 ──
[INFO]  OS:   Debian GNU/Linux 12 (bookworm)
[INFO]  Arch: x86_64
[ OK ]  磁盘可用: 40GB
[ OK ]  网络正常
[ OK ]  基础命令检查通过
[ OK ]  en_US.UTF-8 已生成

── 配置软件源 ──
[ OK ]  已配置阿里云镜像源

── 系统更新 & 基础工具 ──
[INFO]  更新索引...
[ OK ]  基础工具安装完成

── 创建用户 ──
用户名: myuser
密码 (回车=随机生成):
[ OK ]  已生成 20 位随机密码
  1. bash  2. zsh
选择 [1-2]: 1
[ OK ]  用户 myuser 创建成功
[ OK ]  sudo NOPASSWD 配置完成

── 配置 SSH ──
[ OK ]  SSH 服务运行中
SSH 端口 (默认 2077):
粘贴 SSH 公钥 (必填): ssh-ed25519 AAAAC3NzaC1lZDI1...
[ OK ]  SSH 配置完成 (端口: 2077)

── 可选组件 ──
  ── 可多选，输入编号用空格分隔，回车跳过全部 ──

  [1] ZSH + Oh My Zsh
  [2] Docker
  [3] K3s (轻量 Kubernetes)
  [4] 监控工具 (btop / fastfetch)
  [5] 运维面板 (1Panel / 宝塔 / CasaOS)
  [6] WAF (SafeLine 雷池 / BunkerWeb)

输入编号 (空格分隔，回车跳过): 2 4

── Docker ──
[ OK ]  Docker 安装成功
[ OK ]  用户已加入 docker 组

── 监控工具 ──
[ OK ]  监控工具安装完成

── 系统优化 ──
[ OK ]  系统优化完成

═══════════════════════════════════════════════════════
  初始化完成
═══════════════════════════════════════════════════════

  User:     myuser
  Password: xK9#mPq2&vLw5nRj8sA!
  Shell:    /bin/bash
  SSH Port: 2077

  *** 请勿关闭当前窗口！先新开终端测试连接！ ***

═══════════════════════════════════════════════════════
```

### 设计原则

1. **不修改系统 locale** — 通过问答检测终端能力，脚本自身做双语适配，TTY 保持默认
2. **幂等性** — 已安装的包自动跳过，配置项写入前检查去重
3. **安全优先** — 公钥为空直接退出防锁死，SSH 加固后再启用防火墙
4. **`set -euo pipefail`** — 严格模式，命令失败或未定义变量立即停止
5. **国内/海外自适应** — APT 源、Docker 源、Git 仓库、K3s 镜像均自动切换

### 自定义默认值

编辑脚本顶部的常量：

```bash
readonly DEFAULT_SSH_PORT=2077          # 默认 SSH 端口
readonly BASE_PACKAGES=(...)            # 基础工具包列表
readonly SECURITY_PACKAGES=(...)        # 安全工具包列表
readonly FILES_TO_BACKUP=(...)          # 备份文件列表
```

---

## start.sh (启动器)

统一入口脚本，提供菜单选择三个初始化脚本，支持一键远程执行。

### 使用方法

```bash
# 远程一键启动（推荐）
bash <(curl -fsSL https://raw.githubusercontent.com/Mapleawaa/VPS-Init-Tools/main/start.sh)

# 本地运行
wget https://raw.githubusercontent.com/Mapleawaa/VPS-Init-Tools/main/start.sh
chmod +x start.sh
./start.sh
```

### 工作流程

```
start.sh
  ├── [1] init-cn.sh          → 国内 VPS 快速配置
  ├── [2] init-pure-debian.sh → 完整功能 (ZSH/Docker/K3s/面板/WAF)
  ├── [3] vps-init.sh         → 全自动流程 (BBRv3/CrowdSec/CF Tunnel)
  └── [q] 退出
```

---

## init-cn.sh

面向国内 VPS 的快速初始化脚本，详见原 [README](init-cn.md)。

### 核心功能

- SSH 密钥认证 + 端口 2077 + Root/密码禁用
- UFW 防火墙 + Fail2Ban
- ZSH + Oh My Zsh (含插件)
- btop + fastfetch/neofetch
- 国内镜像源 + Git 加速

---

## 前置要求

| 要求 | 说明 |
|------|------|
| **系统** | Debian 10+ / Ubuntu 20.04+ (推荐 Debian 12) |
| **权限** | Root |
| **网络** | 能访问互联网 |
| **磁盘** | 至少 2GB 可用空间 |

---

## 免责声明

使用前请了解脚本功能，建议先在测试环境验证。脚本会修改系统配置文件，请谨慎使用。
