#!/bin/bash

# Lucky 最新版自动安装脚本
# 自动检测 CPU 架构 → 下载对应版本 → 安装 → 启动服务

set -e

# === 配置 ===
GITHUB_REPO="gdy666/lucky"
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
INSTALL_DIR="/usr/local/lucky"
CONFIG_DIR="/etc/lucky"
BIN_PATH="${INSTALL_DIR}/lucky"
SERVICE_FILE="/etc/systemd/system/lucky.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# === 检测 CPU 架构 ===
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)   echo "amd64"   ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armv7)  echo "armv7"   ;;
        *)
            echo -e "${RED}不支持的架构: $arch${NC}"
            exit 1
            ;;
    esac
}

# === 从 GitHub API 获取最新版本号 ===
get_latest_version() {
    echo -e "${YELLOW}正在获取最新版本...${NC}"
    local ver=$(curl -s "$API_URL" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
    if [[ -z "$ver" ]]; then
        echo -e "${RED}无法获取版本号，请检查网络${NC}"
        exit 1
    fi
    echo "$ver"
}

# === 下载并安装 ===
install_lucky() {
    local arch=$1
    local version=$2
    local file_name="lucky_linux_${arch}.tar.gz"
    local url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${file_name}"

    echo -e "${GREEN}下载 Lucky ${version} (${arch})...${NC}"
    curl -L -o "/tmp/${file_name}" "$url"

    echo -e "${GREEN}解压安装到 ${INSTALL_DIR}...${NC}"
    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
    tar -xzf "/tmp/${file_name}" -C "$INSTALL_DIR"
    chmod +x "$BIN_PATH"
    rm -f "/tmp/${file_name}"
}

# === 配置 systemd 服务 ===
setup_service() {
    echo -e "${GREEN}配置 systemd 服务...${NC}"

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Lucky - DDNS & Reverse Proxy
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} -c ${CONFIG_DIR}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable lucky --now
}

# === 主流程 ===
main() {
    echo -e "${YELLOW}=== Lucky 自动安装脚本 ===${NC}"

    ARCH=$(detect_arch)
    echo -e "${GREEN}检测到架构: ${ARCH}${NC}"

    VERSION=$(get_latest_version)
    echo -e "${GREEN}最新版本: ${VERSION}${NC}"

    install_lucky "$ARCH" "$VERSION"
    setup_service

    echo ""
    echo -e "${GREEN}✅ 安装完成${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  访问面板 : http://$(hostname -I | awk '{print $1}'):16601"
    echo "  默认账号 : 666 / 666"
    echo "  配置目录 : ${CONFIG_DIR}"
    echo "  日志查看 : journalctl -u lucky -f"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}⚠️  请立即修改默认密码${NC}"
}

main "$@"
