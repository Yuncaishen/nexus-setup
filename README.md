# Nexus 测试网一键部署脚本

这个脚本可以帮助你在云服务器上快速部署 Nexus 测试网节点。

## 系统要求

- Ubuntu 20.04 或更高版本
- 至少 4GB RAM
- 至少 50GB 可用磁盘空间
- 稳定的网络连接

## 快速开始

1. 使用 root 用户登录你的服务器

2. 下载并运行安装脚本：
```bash
wget https://raw.githubusercontent.com/Yuncaishen/nexus-setup/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

3. 按照提示输入：
   - 你的邮箱地址
   - 你的钱包地址
   - 验证码（从邮箱获取）

## 安装过程

脚本会自动完成以下步骤：

1. 安装系统依赖
2. 安装 Node.js 环境
3. 配置系统参数
4. 注册 Nexus 账户
5. 获取 Prover ID
6. 设置开机自启

## 文件位置

- 配置文件：`/root/nexus/config.json`
- 环境变量：`/root/nexus/.env`
- 访问令牌：`/root/nexus/.access_token`

## 查看状态

- 查看 Prover ID：
```bash
cat /root/nexus/.env
```

- 查看服务状态：
```bash
systemctl status nexus
```

## 常见问题

1. 如果安装失败，检查：
   - 系统要求是否满足
   - 网络连接是否正常
   - 邮箱和钱包地址是否正确

2. 如果服务无法启动：
   - 检查日志：`journalctl -u nexus -f`
   - 确认配置文件是否正确

## 安全建议

- 定期更新系统
- 保护好你的访问令牌和 Prover ID
- 使用强密码
- 配置防火墙

## 支持

如果你遇到任何问题，请：
1. 检查日志文件
2. 查看 [Nexus 官方文档](https://beta.nexus.xyz)
3. 在 GitHub Issues 中提问
