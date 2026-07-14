#!/bin/bash
# AI坤管理工具 - 全平台便携版打包脚本

set -e

VERSION="1.0.0"
PYTHON_VERSION="3.12.4"
RELEASE_DIR="release"
PACK_DIR="AI坤管理工具-Portable"

echo "========================================"
echo "  AI坤管理工具 - 全平台便携版打包"
echo "========================================"
echo ""

# 清理
echo "[1/6] 清理旧文件..."
rm -rf "$PACK_DIR" "$RELEASE_DIR/AI坤管理工具-Portable"*
mkdir -p "$RELEASE_DIR" "$PACK_DIR/app/ui" "$PACK_DIR/python"

# 复制应用文件
echo "[2/6] 复制应用文件..."
cp main.py "$PACK_DIR/app/"
cp model_capabilities.json "$PACK_DIR/app/"
cp ui/index.html "$PACK_DIR/app/ui/"
cp ui/icon.png "$PACK_DIR/app/ui/"
cp ui/icon.ico "$PACK_DIR/app/ui/"

# 复制启动脚本
echo "[3/6] 复制启动脚本..."
cp run.sh "$PACK_DIR/"
cp run.bat "$PACK_DIR/"
chmod +x "$PACK_DIR/run.sh"

# 创建 README
echo "[4/6] 创建说明文件..."
cat > "$PACK_DIR/README.txt" << EOF
AI坤管理工具 - 便携版
======================

使用方法
--------

Windows:
  双击 run.bat

macOS / Linux:
  chmod +x run.sh
  ./run.sh

说明
----

- 首次运行会自动下载 Python（如未安装）
- 所有依赖会自动安装
- 配置文件保存在 ~/.aikun-manager/

系统要求
--------

- Windows 10/11 64位
- macOS 10.15+
- Linux (Ubuntu 20.04+ / Fedora 35+)
EOF

# 打包
echo "[5/6] 打包..."
tar -czf "$RELEASE_DIR/AI坤管理工具-Portable.tar.gz" "$PACK_DIR"

# 计算大小
SIZE=$(du -sh "$RELEASE_DIR/AI坤管理工具-Portable.tar.gz" | cut -f1)

echo "[6/6] 打包完成！"
echo ""
echo "========================================"
echo "  文件: $RELEASE_DIR/AI坤管理工具-Portable.tar.gz"
echo "  大小: $SIZE"
echo "========================================"
echo ""

# 清理
rm -rf "$PACK_DIR"
