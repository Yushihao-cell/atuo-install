#!/bin/bash

# ddns-go 自动安装脚本
# 自动检测 CPU 架构并下载安装最新版

set -e

# === 配置 ===
GH_REPO="jeessy2/ddns-go"
INSTALL_DIR="/usr/local/bin"
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


# === 创建 systemd 服务 ===
setup_service() {
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=ddns-go dynamic DNS
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$BIN_NAME -s install
ExecStop=$INSTALL_DIR/$BIN_NAME -s uninstall
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    log_info "已创建 systemd 服务"
}

    
# === 主流程 ===
main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_err "请使用 root 权限运行 (sudo)"
        exit 1
    fi

    ARCH=$(detect_arch)
    VERSION=$(get_latest_version)

    log_info "检测到架构: $ARCH"
    log_info "最新版本: v$VERSION"

    download_binary "$VERSION" "$ARCH"
    install_binary
    setup_config
    setup_service

    echo ""
    log_info "✅ 安装完成！"
    echo ""
    echo "  二进制: $INSTALL_DIR/$BIN_NAME"
    echo "  服务:   systemctl start $SERVICE_NAME"
    echo ""
    log_info "=========================================="
    log_info "Web管理界面: http://$(hostname -I | awk '{print $1}'):9876"
    log_info "也可以访问: http://localhost:9876"
    log_info "配置文件位置: /root/.ddns_go_config.yaml"
    log_info "服务管理命令:"
    log_info "  启动: systemctl start ddns-go"
    log_info "  停止: systemctl stop ddns-go"
    log_info "  状态: systemctl status ddns-go"
    log_info "  重启: systemctl restart ddns-go"
    log_info "  查看日志: journalctl -u ddns-go -f"
    log_info "=========================================="
    log_info "首次访问Web界面时，需要设置用户名和密码。"
    log_info "如需要卸载，请运行: cd $INSTALL_DIR && ./ddns-go -s uninstall 或者systemctl stop ddns-go"
}

main "$@"
