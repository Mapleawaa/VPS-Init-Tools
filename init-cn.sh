#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 生成随机密码函数 (20位大小写数字混合)
generate_password() {
    local length=20
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local password=""
    
    # 使用 /dev/urandom 生成随机密码
    for ((i=0; i<length; i++)); do
        password="${password}${chars:$((RANDOM % ${#chars})):1}"
    done
    
    echo "$password"
}

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：请使用 Root 用户运行此脚本！${PLAIN}" 
   exit 1
fi

echo -e "${BLUE}=================================================${PLAIN}"
echo -e "${BLUE}      VPS 快速初始化脚本 (Port: 2077)      ${PLAIN}"
echo -e "${BLUE}=================================================${PLAIN}"

# 0. 选择服务器位置
echo -e "${YELLOW}请选择服务器位置以优化网络配置：${PLAIN}"
echo "1. 海外 (正常配置)"
echo "2. 国内 (使用镜像源和代理)"
read -p "请输入选项 [1-2]: " location_choice

IS_CHINA=0
if [[ $location_choice == "2" ]]; then
    IS_CHINA=1
    echo -e "${GREEN}已选择国内模式，将配置镜像源。${PLAIN}"
else
    echo -e "${GREEN}已选择海外模式。${PLAIN}"
fi

# 更新系统
echo -e "${YELLOW}正在更新系统组件...${PLAIN}"
apt update -y && apt upgrade -y
apt install -y curl wget git ufw fail2ban sudo zsh

# 1 & 2 & 3. 用户创建与密钥配置
echo -e "${YELLOW}正在创建用户...${PLAIN}"

# 让用户输入用户名
read -p "请输入要创建的用户名 (将自动转换为小写): " input_username
if [[ -z "$input_username" ]]; then
    echo -e "${RED}错误：用户名不能为空！${PLAIN}"
    exit 1
fi

# 转换为纯小写
USERNAME=$(echo "$input_username" | tr '[:upper:]' '[:lower:]')

echo -e "${GREEN}将创建用户: $USERNAME${PLAIN}"

# 设置密码
read -s -p "请为用户 $USERNAME 设置密码 (直接回车将生成20位随机密码): " user_password
echo

if [[ -z "$user_password" ]]; then
    # 生成随机密码
    user_password=$(generate_password)
    echo -e "${GREEN}已生成随机密码。${PLAIN}"
else
    echo -e "${GREEN}密码已设置。${PLAIN}"
fi

# 创建用户或检测是否已存在
if id "$USERNAME" &>/dev/null; then
    echo -e "${YELLOW}用户 $USERNAME 已存在，跳过创建。${PLAIN}"
else
    useradd -m -s /bin/zsh $USERNAME
    echo "$USERNAME:$user_password" | chpasswd
    echo -e "${GREEN}用户 $USERNAME 创建成功。${PLAIN}"
fi

# 添加用户到sudo组
usermod -aG sudo $USERNAME

# 创建NOPASSWD sudo组并添加用户
NOPASSWD_GROUP="${USERNAME}_nopasswd"
echo -e "${YELLOW}正在配置 sudo 无密码权限...${PLAIN}"

# 创建NOPASSWD组
groupadd $NOPASSWD_GROUP 2>/dev/null || true

# 将用户加入NOPASSWD组
usermod -aG $NOPASSWD_GROUP $USERNAME

# 创建sudo配置文件
cat > /etc/sudoers.d/$USERNAME <<EOF
%${NOPASSWD_GROUP} ALL=(ALL) NOPASSWD: ALL
EOF

# 设置正确的文件权限
chmod 440 /etc/sudoers.d/$USERNAME

echo -e "${GREEN}sudo 无密码权限配置完成。${PLAIN}"

# 获取公钥
echo -e "${YELLOW}请粘贴你的 SSH 公钥 (ssh-rsa/ssh-ed25519 ...):${PLAIN}"
read -p "公钥内容: " USER_PUB_KEY

if [[ -z "$USER_PUB_KEY" ]]; then
    echo -e "${RED}错误：未输入公钥，脚本终止。防止将您锁在门外。${PLAIN}"
    exit 1
fi

# 配置 SSH 目录
USER_HOME="/home/$USERNAME"
mkdir -p "$USER_HOME/.ssh"
echo "$USER_PUB_KEY" > "$USER_HOME/.ssh/authorized_keys"
chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
chown -R $USERNAME:$USERNAME "$USER_HOME/.ssh"

echo -e "${GREEN}SSH 公钥添加成功。${PLAIN}"

# 4 & 2.1. 配置 SSHD (端口 2077，禁止 Root，禁止密码)
echo -e "${YELLOW}正在配置 SSH 服务 (Port 2077)...${PLAIN}"
SSH_CONFIG="/etc/ssh/sshd_config"
cp $SSH_CONFIG "$SSH_CONFIG.bak"

# 使用 sed 修改配置，如果不存在则追加
sed -i 's/^#\?Port .*/Port 2077/' $SSH_CONFIG
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' $SSH_CONFIG
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' $SSH_CONFIG
sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' $SSH_CONFIG

# 检查是否已有 AllowUsers，如果没有建议添加，或者略过(默认允许所有非Root用户)
# 为了安全，这里不强制限制 AllowUsers，防止配置错误，依赖禁止Root和密码已经足够安全。

# 5. 配置防火墙 UFW
echo -e "${YELLOW}正在配置 UFW 防火墙...${PLAIN}"
ufw default deny incoming
ufw default allow outgoing
ufw allow 2077/tcp comment 'SSH Custom Port'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
# 强制开启，不询问
echo "y" | ufw enable
echo -e "${GREEN}防火墙配置完毕。${PLAIN}"

# 6. 配置 Fail2Ban
echo -e "${YELLOW}正在配置 Fail2Ban...${PLAIN}"
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 2077
EOF
systemctl restart fail2ban
echo -e "${GREEN}Fail2Ban 已启动并监控端口 2077。${PLAIN}"

# 7 & 8. 安装 Zsh 及插件 (Oh My Zsh)
echo -e "${YELLOW}正在配置 Zsh 环境...${PLAIN}"

# 如果是国内，设置 git 代理或使用镜像源安装 OMZ (这里使用 gitee 镜像作为示例，或者 ghproxy)
OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
if [[ $IS_CHINA -eq 1 ]]; then
    # 使用国内加速
    OMZ_INSTALL_URL="https://install.ohmy.schue.we.cn/ohmyzsh.sh" 
fi

# 无人值守安装 Oh My Zsh 到 Maple 用户
sudo -u $USERNAME sh -c "$(curl -fsSL $OMZ_INSTALL_URL)" "" --unattended

# 安装插件 (Autosuggestions & Syntax Highlighting)
ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"
if [[ $IS_CHINA -eq 1 ]]; then
    sudo -u $USERNAME git clone https://ghfast.top/https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
    sudo -u $USERNAME git clone https://ghfast.top/https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
else
    sudo -u $USERNAME git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
    sudo -u $USERNAME git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
fi

# 修改 .zshrc 启用插件
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$USER_HOME/.zshrc"
# 修改主题 (可选，这里保持默认 robbyrussell 或者改为 ys)
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' "$USER_HOME/.zshrc"

echo -e "${GREEN}Zsh 环境配置完毕。${PLAIN}"

# 9. Docker 安装已移除

# # 将 Maple 加入 docker 组
# usermod -aG docker $USERNAME
# echo -e "${GREEN}Docker 安装完毕，用户 Maple 已加入 Docker 组。${PLAIN}"

# 10. 安装 btop 和 fastfetch
echo -e "${YELLOW}正在安装监控工具...${PLAIN}"
# Btop
if [[ $IS_CHINA -eq 1 ]]; then
     # 这里简化处理，直接用 apt，如果版本太老可以考虑下载 release
     apt install -y btop
else
     apt install -y btop
fi

# Fastfetch (如果 apt 源里没有，尝试下载 deb，这里以 apt 为主，兼容性更好)
# Ubuntu 24.04+ 或较新 Debian 才有 fastfetch，如果没有则尝试安装 neofetch 作为替补
if apt-cache show fastfetch >/dev/null 2>&1; then
    apt install -y fastfetch
    # 在 zshrc 末尾添加 fastfetch
    echo "fastfetch" >> "$USER_HOME/.zshrc"
else
    echo -e "${YELLOW}软件源未找到 fastfetch，尝试安装 neofetch...${PLAIN}"
    apt install -y neofetch
    echo "neofetch" >> "$USER_HOME/.zshrc"
fi

# 11. 结束
echo -e "${BLUE}=================================================${PLAIN}"
echo -e "${GREEN} 所有配置已完成！ ${PLAIN}"
echo -e "${BLUE}=================================================${PLAIN}"
echo -e "用户信息："
echo -e "用户名: ${GREEN}$USERNAME${PLAIN}"
echo -e "密码: ${YELLOW}$user_password${PLAIN}"
echo -e "SSH端口: ${RED}2077${PLAIN}"
echo -e ""
echo -e "请注意："
echo -e "1. SSH 端口已改为: ${RED}2077${PLAIN}"
echo -e "2. Root 登录已禁用，密码登录已禁用。"
echo -e "3. 请使用用户: ${GREEN}$USERNAME${PLAIN} 和你的 ${YELLOW}私钥${PLAIN} 登录。"
echo -e "4. 命令示例: ssh -p 2077 $USERNAME@<Server-IP>"
echo -e "5. 该用户拥有 sudo 无密码权限。"
echo -e "${RED}*** 重要: 请不要关闭当前窗口，立即新开一个终端测试能否连接！ ***${PLAIN}"
echo -e "${RED}*** 测试成功后再重启 SSH 服务或重启服务器！ ***${PLAIN}"
echo -e "${BLUE}=================================================${PLAIN}"

# 询问是否重启 SSH 服务
read -p "是否立即重启 SSH 服务以应用更改？(y/n): " restart_ssh
if [[ $restart_ssh == "y" ]]; then
    systemctl restart ssh
    echo -e "${GREEN}SSH 服务已重启。请进行测试。${PLAIN}"
fi