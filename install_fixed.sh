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
if [ "$EUID" -ne 0 ] 
then
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
    read -p "请输入你的钱包地址: " ADDRESS
    
    # 验证输入
    if [ -z "$EMAIL" ] || [ -z "$ADDRESS" ]; then
        log_error "邮箱和钱包地址不能为空"
        exit 1
    fi
    
    # 保存配置
    mkdir -p /root/nexus
    cat > /root/nexus/config.json << EOF
{
    "email": "$EMAIL",
    "wallet_address": "$ADDRESS"
}
EOF
}

# 安装 HTTPS API 依赖
install_https_dependency() {
    log_info "正在安装 HTTPS API 依赖..."
    cd /root/nexus
    npm init -y
}

# 创建注册客户端
create_client() {
    log_info "正在创建注册客户端..."
    cat > /root/nexus/client.js << 'EOF'
const https = require('https');
const fs = require('fs');

const config = JSON.parse(fs.readFileSync('/root/nexus/config.json', 'utf8'));

function makeRequest(options, data = null) {
    return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
            let responseData = '';
            
            res.on('data', (chunk) => {
                responseData += chunk;
            });
            
            res.on('end', () => {
                try {
                    const jsonResponse = JSON.parse(responseData);
                    resolve(jsonResponse);
                } catch (error) {
                    console.log('Raw response:', responseData);
                    reject(new Error('Invalid JSON response'));
                }
            });
        });
        
        req.on('error', (error) => {
            reject(error);
        });
        
        if (data) {
            req.write(JSON.stringify(data));
        }
        req.end();
    });
}

async function register() {
    try {
        // 注册
        console.log('Registering...');
        const registerOptions = {
            hostname: 'api.nexus.xyz',
            port: 443,
            path: '/register',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            },
            rejectUnauthorized: false
        };
        
        const registerData = {
            email: config.email,
            address: config.wallet_address
        };
        
        const registerResponse = await makeRequest(registerOptions, registerData);
        console.log('Register response:', registerResponse);
        
        if (!registerResponse.success) {
            throw new Error('Registration failed: ' + registerResponse.message);
        }
        
        // 等待验证码
        const code = await new Promise((resolve) => {
            const readline = require('readline').createInterface({
                input: process.stdin,
                output: process.stdout
            });
            
            readline.question('Please enter the verification code from your email: ', (code) => {
                readline.close();
                resolve(code);
            });
        });
        
        // 验证
        console.log('Verifying...');
        const verifyOptions = {
            hostname: 'api.nexus.xyz',
            port: 443,
            path: '/verify',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            },
            rejectUnauthorized: false
        };
        
        const verifyData = {
            email: config.email,
            code: code
        };
        
        const verifyResponse = await makeRequest(verifyOptions, verifyData);
        console.log('Verify response:', verifyResponse);
        
        if (!verifyResponse.success) {
            throw new Error('Verification failed: ' + verifyResponse.message);
        }
        
        // 保存 Prover ID
        if (verifyResponse.prover_id) {
            fs.writeFileSync('/root/nexus/.env', `PROVER_ID=${verifyResponse.prover_id}\n`);
            console.log('Saved Prover ID:', verifyResponse.prover_id);
        }
        
        process.exit(0);
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

register();
EOF
}

# 运行注册客户端
run_client() {
    log_info "正在运行注册客户端..."
    cd /root/nexus
    node client.js
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
    install_https_dependency
    create_client
    run_client
    setup_autostart
    
    log_info "安装完成！"
}

# 运行主函数
main
