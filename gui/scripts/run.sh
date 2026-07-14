#!/bin/bash
# AI坤管理工具 - 跨平台启动脚本
# 自动检测 Python，如果没有则下载便携版

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
PYTHON_DIR="$SCRIPT_DIR/python"
PYTHON_VERSION="3.12.4"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "  AI坤管理工具 - 启动"
echo "========================================"
echo ""

# 检测系统
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux*)     PLATFORM="linux";;
    Darwin*)    PLATFORM="macos";;
    MINGW*|MSYS*|CYGWIN*)    PLATFORM="windows";;
    *)          echo -e "${RED}不支持的系统: $OS${NC}"; exit 1;;
esac

case "$ARCH" in
    x86_64|amd64)   ARCH_NAME="x86_64";;
    arm64|aarch64)  ARCH_NAME="aarch64";;
    *)              ARCH_NAME="$ARCH";;
esac

echo -e "系统: ${GREEN}$PLATFORM${NC} ($ARCH_NAME)"

# 查找 Python
find_python() {
    # 优先使用便携版
    if [ -f "$PYTHON_DIR/bin/python3" ]; then
        echo "$PYTHON_DIR/bin/python3"
        return 0
    fi
    
    # 尝试系统 Python
    if command -v python3 &>/dev/null; then
        echo "python3"
        return 0
    fi
    
    if command -v python &>/dev/null; then
        echo "python"
        return 0
    fi
    
    return 1
}

# 下载便携版 Python
download_portable_python() {
    echo -e "${YELLOW}[提示] 未检测到 Python，正在下载便携版...${NC}"
    
    mkdir -p "$PYTHON_DIR"
    
    if [ "$PLATFORM" = "macos" ]; then
        if [ "$ARCH_NAME" = "aarch64" ]; then
            PYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg"
        else
            PYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/python-$PYTHON_VERSION-macos11.pkg"
        fi
        # macOS 使用系统自带 Python 或提示安装
        echo -e "${YELLOW}macOS 通常自带 Python，请尝试:${NC}"
        echo "  xcode-select --install"
        echo "  或访问 https://www.python.org/downloads/macos/"
        exit 1
    fi
    
    # Linux
    if [ "$ARCH_NAME" = "aarch64" ]; then
        PYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION-linux-aarch64.tar.xz"
    else
        PYTHON_URL="https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION-linux-x86_64.tar.xz"
    fi
    
    echo "下载 Python $PYTHON_VERSION ..."
    curl -L -o "$PYTHON_DIR/python.tar.xz" "$PYTHON_URL" 2>&1
    
    echo "解压 Python ..."
    tar -xf "$PYTHON_DIR/python.tar.xz" -C "$PYTHON_DIR" --strip-components=1
    rm -f "$PYTHON_DIR/python.tar.xz"
    
    echo -e "${GREEN}Python 便携版下载完成${NC}"
}

# 主流程
PYTHON_CMD=$(find_python) || {
    download_portable_python
    PYTHON_CMD=$(find_python) || {
        echo -e "${RED}无法获取 Python，请手动安装${NC}"
        exit 1
    }
}

echo -e "Python: ${GREEN}$PYTHON_CMD${NC}"

# 检查依赖
echo "检查依赖..."
if ! $PYTHON_CMD -c "import webview" &>/dev/null; then
    echo "安装依赖..."
    if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
        $PYTHON_CMD -m pip install -r "$SCRIPT_DIR/requirements.txt" -q 2>/dev/null || \
        $PYTHON_CMD -m pip install pywebview requests pillow -q
    else
        $PYTHON_CMD -m pip install pywebview requests pillow -q
    fi
fi

# 启动程序
echo ""
echo "启动 AI坤管理工具..."
cd "$APP_DIR"
$PYTHON_CMD main.py
