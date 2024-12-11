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

log_debug() {
    echo -e "${YELLOW}[DEBUG]${NC} $1"
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
}

# 配置系统环境
setup_system() {
    log_info "正在配置系统环境..."
    timedatectl set-timezone Asia/Shanghai
    
    # 配置系统限制
    cat > /etc/security/limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
EOF

    # 配置系统参数
    cat > /etc/sysctl.d/99-nexus.conf << 'EOF'
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
    
    if [ -z "$EMAIL" ] || [ -z "$WALLET_ADDRESS" ]; then
        log_error "邮箱和钱包地址不能为空"
        exit 1
    fi
    
    mkdir -p /root/nexus
    cat > /root/nexus/config.json << EOF
{
    "email": "$EMAIL",
    "wallet_address": "$WALLET_ADDRESS"
}
EOF

    log_debug "创建的配置文件内容："
    cat /root/nexus/config.json
}

# 注册账户
register_account() {
    log_info "开始注册账户..."
    
    # 显示请求内容
    log_debug "发送注册请求，请求内容："
    cat /root/nexus/config.json
    
    # 发送请求并保存完整响应
    FULL_RESPONSE=$(curl -v -X POST "https://beta.nexus.xyz/api/register" \
        -H "Content-Type: application/json" \
        -d @/root/nexus/config.json 2>&1)
    
    log_debug "API 完整响应："
    echo "$FULL_RESPONSE"
    
    # 提取响应体
    RESPONSE=$(echo "$FULL_RESPONSE" | grep "^{" || echo "{}")
    
    log_debug "解析的响应体："
    echo "$RESPONSE"
    
    # 检查响应
    if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "{}" ]; then
        log_error "API 响应为空或无效"
        exit 1
    fi
    
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success' 2>/dev/null || echo "false")
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message' 2>/dev/null || echo "未知错误")
    
    if [ "$SUCCESS" != "true" ]; then
        log_error "注册失败: $MESSAGE"
        log_debug "完整错误信息："
        echo "$FULL_RESPONSE"
        exit 1
    fi
    
    log_info "注册请求已发送，请检查邮箱获取验证码"
    read -p "请输入收到的验证码: " VERIFICATION_CODE
    
    # 验证码请求
    VERIFY_DATA="{\"email\": \"$EMAIL\", \"code\": \"$VERIFICATION_CODE\"}"
    log_debug "发送验证请求，请求内容："
    echo "$VERIFY_DATA"
    
    FULL_RESPONSE=$(curl -v -X POST "https://beta.nexus.xyz/api/verify" \
        -H "Content-Type: application/json" \
        -d "$VERIFY_DATA" 2>&1)
    
    log_debug "验证 API 完整响应："
    echo "$FULL_RESPONSE"
    
    RESPONSE=$(echo "$FULL_RESPONSE" | grep "^{" || echo "{}")
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success' 2>/dev/null || echo "false")
    MESSAGE=$(echo "$RESPONSE" | jq -r '.message' 2>/dev/null || echo "未知错误")
    
    if [ "$SUCCESS" != "true" ]; then
        log_error "验证失败: $MESSAGE"
        log_debug "完整错误信息："
        echo "$FULL_RESPONSE"
        exit 1
    fi
    
    echo "$RESPONSE" | jq -r '.access_token' > /root/nexus/.access_token
    log_info "账户验证成功"
}

# 获取并保存 Prover ID
get_prover_id() {
    if [ ! -f "/root/nexus/.access_token" ]; then
        log_error "访问令牌不存在！"
        exit 1
    fi
    
    ACCESS_TOKEN=$(cat /root/nexus/.access_token)
    
    log_debug "发送 Prover ID 请求..."
    FULL_RESPONSE=$(curl -v -X GET "https://beta.nexus.xyz/api/prover-id" \
        -H "Authorization: Bearer $ACCESS_TOKEN" 2>&1)
    
    log_debug "Prover ID API 完整响应："
    echo "$FULL_RESPONSE"
    
    RESPONSE=$(echo "$FULL_RESPONSE" | grep "^{" || echo "{}")
    PROVER_ID=$(echo "$RESPONSE" | jq -r '.prover_id' 2>/dev/null)
    
    if [ -z "$PROVER_ID" ]; then
        log_error "获取 Prover ID 失败"
        log_debug "完整错误信息："
        echo "$FULL_RESPONSE"
        exit 1
    fi
    
    echo "PROVER_ID=$PROVER_ID" > /root/nexus/.env
    log_info "已获取并保存 Prover ID: $PROVER_ID"
}

# 设置开机自启
setup_autostart() {
    log_info "配置开机自启..."
    
    cat > /etc/systemd/system/nexus.service << 'EOF'
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
