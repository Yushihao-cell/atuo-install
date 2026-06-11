#!/bin/bash
#author:Eric
# ddns-go 自动安装脚本和创建卸载脚本
# 自动检测 CPU 架构并下载安装最新版

set -e

# === 配置 ===
GH_REPO="jeessy2/ddns-go"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/ddns-go"
BIN_NAME="ddns-go"
SERVICE_NAME="ddns-go"

# === 颜色输出 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# === 架构检测 ===
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)   echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv7) echo "armv7" ;;
        mips64)   echo "mips64le" ;;
        mips|mipsel) echo "mipsle" ;;
        *)        log_err "不支持的架构: $arch"; exit 1 ;;
    esac
}

# === 获取最新版本号 ===
get_latest_version() {
    curl -s "https://api.github.com/repos/$GH_REPO/releases/latest" | \
    grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/'
}

# === 下载文件 ===
download_binary() {
    local version=$1
    local arch=$2
    local url="https://github.com/$GH_REPO/releases/download/v${version}/${BIN_NAME}_${version}_linux_${arch}.tar.gz"

    log_info "下载地址: $url"

    if ! curl -L -o "/tmp/${BIN_NAME}.tar.gz" "$url"; then
        log_err "下载失败，请检查网络或手动访问: $url"
        exit 1
    fi

    tar -xzf "/tmp/${BIN_NAME}.tar.gz" -C /tmp
    mv /tmp/${BIN_NAME} /tmp/${BIN_NAME}_bin
}

# === 安装二进制 ===
install_binary() {
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
    fi

    cp /tmp/${BIN_NAME}_bin "$INSTALL_DIR/$BIN_NAME"
    chmod +x "$INSTALL_DIR/$BIN_NAME"
    log_info "已安装到: $INSTALL_DIR/$BIN_NAME"
}
  
# === 创建配置目录 ===
setup_config() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        log_info "已创建配置目录: $CONFIG_DIR"
    fi
}

# === 安装服务（使用内置命令）===
install_service() {
    # 使用 ddns-go 内置的 install 命令
    $INSTALL_DIR/$BIN_NAME -s install -c "$CONFIG_DIR/${BIN_NAME}_config.yaml"
    log_info "已通过内置命令安装服务"
}

# === 创建 systemd 服务 ===
setup_service() {
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=ddns-go dynamic DNS
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BIN_NAME -f 60 -l :9876 -c $CONFIG_DIR/${BIN_NAME}_config.yaml
Restart=always
RestartSec=120
EnvironmentFile=-/etc/sysconfig/ddns-go

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    log_info "已创建 systemd 服务"
}

# === 创建卸载脚本 ===
create_uninstall_script() {
    cat > $CONFIG_DIR/uninstall.sh <<'EOF'
#!/bin/bash

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# 配置
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/ddns-go"
BIN_NAME="ddns-go"
SERVICE_NAME="ddns-go"

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    log_err "请使用 root 权限运行 (sudo)"
    exit 1
fi

log_info "开始卸载 ddns-go..."

 # 检查系统是否支持 systemd
    if  command -v systemctl &> /dev/null; then

# 停止并禁用服务
if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "停止服务..."
    systemctl stop $SERVICE_NAME
fi

if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
    log_info "禁用服务..."
    systemctl disable $SERVICE_NAME
fi
    fi

# 删除服务文件
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    log_info "已删除服务文件"
fi

# 使用内置命令卸载（如果二进制还存在）
if [ -f "$INSTALL_DIR/$BIN_NAME" ]; then
    log_info "执行内置卸载命令..."
    $INSTALL_DIR/$BIN_NAME -s uninstall 2>/dev/null || true
fi

# 删除二进制文件
if [ -f "$INSTALL_DIR/$BIN_NAME" ]; then
    rm -f "$INSTALL_DIR/$BIN_NAME"
    log_info "已删除二进制文件"
fi

# 删除配置目录（可选，会询问用户）
read -p "是否删除配置目录 $CONFIG_DIR? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$CONFIG_DIR"
    log_info "已删除配置目录"
else
    log_warn "保留配置目录: $CONFIG_DIR"
fi

# 清理临时文件
rm -f /tmp/${BIN_NAME}.tar.gz /tmp/${BIN_NAME}_bin 2>/dev/null

log_info "✅ ddns-go 卸载完成！"
EOF

    chmod +x $CONFIG_DIR/uninstall.sh
    log_info "已创建卸载脚本: $CONFIG_DIR/uninstall.sh"
}

# === 主流程 ===
main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_err "请使用 root 权限运行 (sudo)"
        exit 1
    fi

    # 检查是否已安装
    if [ -f "$INSTALL_DIR/$BIN_NAME" ]; then
        log_warn "检测到已安装的 Lucky"
        read -p "是否覆盖安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            exit 0
        fi
    fi

    ARCH=$(detect_arch)
    VERSION=$(get_latest_version)

    log_info "检测到架构: $ARCH"
    log_info "最新版本: v$VERSION"

    download_binary "$VERSION" "$ARCH"
    install_binary
    install_service
    setup_config
    create_uninstall_script
    
    echo ""
    log_info "✅ 安装完成！"
    echo ""
    echo "  二进制: $INSTALL_DIR/$BIN_NAME"
    echo "  配置目录: $CONFIG_DIR"
    echo ""
    log_info "=========================================="

    # 获取本机 IP
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "$LOCAL_IP" ]; then
        log_info "Web 管理界面: http://${LOCAL_IP}:9876"
    fi

    log_info "也可以访问: http://localhost:9876"
    log_info "配置文件位置: $CONFIG_DIR/${BIN_NAME}_config.yaml"
    log_info "=========================================="
    log_info "首次访问Web界面时，需要设置用户名和密码。"
    log_warn "如需要卸载，请运行: $CONFIG_DIR/uninstall.sh"
    echo ""

 # 检查系统是否支持 systemd
    if  command -v systemctl &> /dev/null; then
    setup_service
    log_info "服务管理命令:"
    log_info "  启动: systemctl start $SERVICE_NAME"
    log_info "  状态: systemctl status $SERVICE_NAME"
    log_info "  重启: systemctl restart $SERVICE_NAME"
    log_info "  停止: systemctl stop $SERVICE_NAME"
    log_info "  查看日志: journalctl -u $SERVICE_NAME -f"
    fi
}

main "$@"
