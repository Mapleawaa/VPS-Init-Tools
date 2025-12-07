# VPS 快速初始化脚本

一个专为 VPS 服务器设计的快速初始化脚本，用于自动化配置服务器基础环境和安全设置。

## 项目简介

这个脚本能够快速将新购买的 VPS 服务器配置为生产就绪状态，包括用户管理、SSH 安全配置、防火墙设置、监控工具安装等常见需求。支持国内外服务器环境智能优化。

## 主要功能

### 🔐 安全配置
- **SSH 密钥认证**：支持 RSA/ED25519 公钥认证，完全禁用密码登录
- **自定义 SSH 端口**：默认改为 2077 端口，避免默认端口扫描
- **Root 登录禁用**：提高服务器安全性
- **Fail2Ban 防护**：自动检测和阻止暴力破解攻击
- **UFW 防火墙**：配置基本访问控制策略

### 👤 用户管理
- **自定义用户名**：允许用户输入用户名，自动转换为小写
- **密码管理**：支持自定义密码或自动生成20位随机密码
- **Zsh 环境配置**：安装 Oh My Zsh 及常用插件（自动补全、语法高亮）
- **美化终端**：配置 ys 主题，提升终端使用体验
- **无密码 sudo**：配置 NOPASSWD sudo 权限，提升操作便利性

### 🛠️ 系统优化
- **智能源选择**：根据服务器位置自动选择最优软件源
- **基础工具安装**：curl、wget、git、htop、fail2ban 等
- **监控工具**：btop、fastfetch/neofetch 系统信息显示
- **自动系统更新**：安装最新安全补丁

### 🌍 网络优化
- **国内外自适应**：智能识别服务器位置并优化网络配置
- **国内镜像源**：使用国内加速源提升安装速度
- **代理支持**：为国内环境配置 Git 代理

## 使用方法

### 前置要求

- Ubuntu/Debian 系统
- Root 权限访问
- 稳定的网络连接

### 安装步骤

1. **上传脚本文件到服务器**
   ```bash
   # 将 init-cn.sh 上传到服务器，例如：
   scp init-cn.sh root@your-server-ip:/root/
   ```

2. **给脚本执行权限**
   ```bash
   chmod +x init-cn.sh
   ```

3. **运行脚本**
   ```bash
   ./init-cn.sh
   ```

4. **按提示操作**
   - 选择服务器位置（国内/海外）
   - 输入你的 SSH 公钥

### 使用示例

```bash
# 运行初始化脚本
sudo ./init-cn.sh

# 选择服务器位置
请选择服务器位置以优化网络配置：
1. 海外 (正常配置)
2. 国内 (使用镜像源和代理)
请输入选项 [1-2]: 2

# 输入用户名 (自动转换为小写)
请输入要创建的用户名 (将自动转换为小写): MyUser
将创建用户: myuser

# 设置密码 (直接回车生成随机密码)
请为用户 myuser 设置密码 (直接回车将生成20位随机密码):
[直接回车]
已生成随机密码。

# 输入 SSH 公钥
请粘贴你的 SSH 公钥 (ssh-rsa/ssh-ed25519 ...):
公钥内容: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7...

# 查看创建的用户信息
用户信息：
用户名: myuser
密码: AbCdEfGhIjKlMnOpQrSt
SSH端口: 2077

# 重启 SSH 服务
是否立即重启 SSH 服务以应用更改？(y/n): y
```

### 连接测试

配置完成后，使用以下命令连接服务器：

```bash
# 使用自定义端口连接 (替换 username 为实际用户名)
ssh -p 2077 username@your-server-ip

# 或使用 SSH 配置
vim ~/.ssh/config
```

## 配置详情

### SSH 配置
- **端口**：2077
- **认证方式**：仅允许公钥认证
- **Root 登录**：禁用
- **密码认证**：禁用

### 防火墙规则
- **入站**：仅允许 SSH(2077)、HTTP(80)、HTTPS(443)
- **出站**：允许所有
- **默认策略**：拒绝入站，允许出站

### 用户权限
- **用户名**：用户自定义（自动转换为小写）
- **Shell**：/bin/zsh
- **权限**：sudo 权限 + 无密码 sudo (NOPASSWD)
- **插件**：git、zsh-autosuggestions、zsh-syntax-highlighting
- **密码**：用户自定义或20位随机密码

### 监控工具
- **btop**：系统资源监控
- **fastfetch/neofetch**：系统信息显示
- **fail2ban**：安全监控

## 重要提醒

⚠️ **连接测试**
- 脚本运行完成后，请**立即新开终端**测试连接
- 测试命令：`ssh -p 2077 maple@your-server-ip`
- 测试成功后再重启服务器

⚠️ **备份建议**
- 脚本会自动备份 SSH 配置文件为 `sshd_config.bak`
- 建议在运行前手动备份重要数据

⚠️ **网络要求**
- 确保服务器能够访问互联网
- 国内服务器建议选择"国内模式"以获得更好体验

## 故障排除

### 连接失败
1. 检查防火墙是否正确开放 2077 端口
2. 确认 SSH 公钥格式正确（以 `ssh-rsa` 或 `ssh-ed25519` 开头）
3. 检查云服务商安全组设置
4. 确认用户名是否正确（已自动转换为小写）

### 新功能使用注意事项
1. **用户名转换**：输入的用户名会自动转换为小写，例如 "MyUser" → "myuser"
2. **密码生成**：直接回车可生成20位随机密码，建议妥善保存
3. **无密码 sudo**：用户具有 sudo 无密码权限，使用时需谨慎操作
4. **用户信息显示**：脚本结束后会显示创建的用户名和密码，请务必记录

### 脚本执行错误
1. 确认以 Root 权限运行
2. 检查网络连接是否正常
3. 确认系统为 Ubuntu/Debian

### 插件安装失败
脚本会自动使用国内镜像源，如果仍有问题，可以手动安装：
```bash
# 手动安装 Oh My Zsh
sh -c "$(curl -fsSL https://install.ohmy.schue.we.cn/ohmyzsh.sh)"

# 手动安装插件
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
```

## 自定义配置

如需修改默认配置，可以编辑脚本中的以下变量：

```bash
# 默认用户名
USERNAME="maple"

# SSH 端口
SSH_PORT="2077"

# 主题设置
ZSH_THEME="ys"
```

## 许可证

本项目采用 MIT 许可证，详情请查看 LICENSE 文件。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个脚本！

---

**免责声明**：使用本脚本前请确保了解其功能，并建议在测试环境中先行验证。脚本会修改系统配置，请谨慎使用。