#!/bin/bash
# AI坤 × OpenClaw 管理工具 - Linux/macOS 打包脚本

echo "========================================"
echo "  AI坤 × OpenClaw 管理工具 - 打包"
echo "========================================"
echo ""

# 检测系统
OS="$(uname -s)"
case "$OS" in
    Linux*)     PLATFORM="Linux";;
    Darwin*)    PLATFORM="macOS";;
    *)          echo "不支持的系统: $OS"; exit 1;;
esac
echo "检测到系统: $PLATFORM"

# 检查依赖
echo "[1/4] 检查依赖..."
python3 -c "import pywebview; import PyInstaller" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "缺少依赖，正在安装..."
    pip3 install pywebview pyinstaller -q
fi

# 清理旧构建
echo "[2/4] 清理旧构建..."
rm -rf build dist

# 打包
echo "[3/4] 正在打包（可能需要 2-5 分钟）..."
pyinstaller build.spec --clean --noconfirm 2>&1

# 检查结果
echo "[4/4] 检查打包结果..."
if [ "$PLATFORM" = "macOS" ]; then
    if [ -d "dist/AI坤管理工具.app" ]; then
        echo ""
        echo "========================================"
        echo "  打包成功！"
        echo "  输出文件: dist/AI坤管理工具.app"
        echo "========================================"
        open dist
    fi
else
    if [ -f "dist/AI坤管理工具" ]; then
        echo ""
        echo "========================================"
        echo "  打包成功！"
        echo "  输出文件: dist/AI坤管理工具"
        echo "========================================"
        chmod +x "dist/AI坤管理工具"
        ls -lh "dist/AI坤管理工具"
    fi
fi
