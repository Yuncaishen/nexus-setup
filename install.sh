#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否是 root 用户
if [ "$EUID" -ne 0 ]; then 
    log_error "请使用 root 用户运行此脚本"
    exit 1
fi

# 安装基础依赖
install_dependencies() {
    log_info "正在安装基础依赖..."
    apt update
    apt install -y curl wget git jq build-essential
}

# 安装 Node.js
install_nodejs() {
    log_info "正在安装 Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
    apt install -y nodejs
    
    # 验证安装
    node_version=$(node --version)
    npm_version=$(npm --version)
    log_info "Node.js 版本: $node_version"
    log_info "npm 版本: $npm_version"
}

# 配置系统环境
setup_system() {
    log_info "正在配置系统环境..."
    
    # 设置时区
    timedatectl set-timezone Asia/Shanghai
    
    # 增加系统限制
    cat > /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
EOF
    
    # 设置系统参数
    cat > /etc/sysctl.d/99-nexus.conf << EOF
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
EOF
    
    sysctl -p /etc/sysctl.d/99-nexus.conf
}

# 获取用户输入
get_user_input() {
    log_info "请输入配置信息"
    
    read -p "请输入你的邮箱地址: " EMAIL
    read -p "请输入你的钱包地址: " WALLET_ADDRESS
    
    # 验证输入
    if [ -z "$EMAIL" ] || [ -z "$WALLET_ADDRESS" ]; then
        log_error "邮箱和钱包地址不能为空"
        exit 1
    fi
    
    # 保存配置
    mkdir -p /root/nexus
    cat > /root/nexus/config.json << EOF
{
    "email": "$EMAIL",
    "wallet_address": "$WALLET_ADDRESS",
    "api_base_url": "https://beta.nexus.xyz",
    "chain_id": "5",
    "gas_limit": "3000000"
}
EOF
}

# 注册账户
register_account() {
    log_info "开始注册账户..."
    
    RESPONSE=$(curl -s -X POST "https://beta.nexus.xyz/api/register" \
        -H "Content-Type: application/json" \
        -d @/root/nexus/config.json)
    
    if [ "$(echo $RESPONSE | jq -r '.success')" != "true" ]; then
        log_error "注册失败: $(echo $RESPONSE | jq -r '.message')"
        exit 1
    fi
    
    log_info "注册请求已发送，请检查邮箱获取验证码"
    
    # 等待验证码输入
    read -p "请输入收到的验证码: " VERIFICATION_CODE
    
    RESPONSE=$(curl -s -X POST "https://beta.nexus.xyz/api/verify" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$EMAIL\",
            \"code\": \"$VERIFICATION_CODE\"
        }")
    
    if [ "$(echo $RESPONSE | jq -r '.success')" != "true" ]; then
        log_error "验证失败: $(echo $RESPONSE | jq -r '.message')"
        exit 1
    fi
    
    # 保存访问令牌
    echo $RESPONSE | jq -r '.access_token' > /root/nexus/.access_token
    log_info "账户验证成功"
}

# 获取并保存 Prover ID
get_prover_id() {
    if [ ! -f "/root/nexus/.access_token" ]; then
        log_error "访问令牌不存在！"
        exit 1
    fi
    
    ACCESS_TOKEN=$(cat /root/nexus/.access_token)
    
    RESPONSE=$(curl -s -X GET "https://beta.nexus.xyz/api/prover-id" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    
    PROVER_ID=$(echo $RESPONSE | jq -r '.prover_id')
    
    if [ -z "$PROVER_ID" ]; then
        log_error "获取 Prover ID 失败"
        exit 1
    fi
    
    # 保存 Prover ID
    echo "PROVER_ID=$PROVER_ID" > /root/nexus/.env
    log_info "已获取并保存 Prover ID: $PROVER_ID"
}

# 设置开机自启
setup_autostart() {
    log_info "配置开机自启..."
    
    # 创建服务文件
    cat > /etc/systemd/system/nexus.service << EOF
[Unit]
Description=Nexus Testnet Node
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/nexus
Environment=NODE_ENV=production
ExecStart=/usr/bin/node /root/nexus/index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载服务
    systemctl daemon-reload
    systemctl enable nexus
}

# 主函数
main() {
    log_info "开始安装 Nexus 测试网..."
    
    install_dependencies
    install_nodejs
    setup_system
    get_user_input
    register_account
    get_prover_id
    setup_autostart
    
    log_info "安装完成！"
    log_info "你的 Prover ID 已保存在 /root/nexus/.env 文件中"
    log_info "请使用以下命令查看："
    log_info "cat /root/nexus/.env"
}

# 运行主函数
main
