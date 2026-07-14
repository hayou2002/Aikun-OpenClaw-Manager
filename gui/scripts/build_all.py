#!/usr/bin/env python3
"""
AI坤管理工具 - 跨平台打包脚本
支持 Windows / macOS / Linux
"""

import os
import sys
import shutil
import subprocess
import platform
from pathlib import Path

PLATFORM = platform.system()
PROJECT_DIR = Path(__file__).parent

def run_cmd(cmd, check=True):
    """运行命令"""
    print(f"  运行: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0 and check:
        print(f"  错误: {result.stderr}")
        return False
    return True

def clean_personal_data():
    """清理个人配置文件"""
    print("\n[1/5] 清理个人配置...")
    
    # 清理缓存文件
    cache_files = [
        ".aikun_cache.json",
        ".aikun_session.json",
        "model_capabilities.json",
    ]
    
    for f in cache_files:
        fpath = PROJECT_DIR / f
        if fpath.exists():
            fpath.unlink()
            print(f"  已删除: {f}")
    
    # 清理构建目录
    for d in ["dist", "build", "__pycache__"]:
        dpath = PROJECT_DIR / d
        if dpath.exists():
            shutil.rmtree(dpath)
            print(f"  已删除: {d}")

def install_dependencies():
    """安装依赖"""
    print("\n[2/5] 安装依赖...")
    return run_cmd(f"{sys.executable} -m pip install pywebview requests pyinstaller --quiet")

def build_exe():
    """打包 exe"""
    print("\n[3/5] 打包 exe...")
    
    icon_path = PROJECT_DIR / "ui" / "icon.ico"
    icon_arg = f"--icon={icon_path}" if icon_path.exists() else ""
    
    # 添加 UI 文件作为数据文件
    ui_dir = PROJECT_DIR / "ui"
    data_arg = f"--add-data={ui_dir};ui" if PLATFORM == "Windows" else f"--add-data={ui_dir}:ui"
    
    cmd = f'{sys.executable} -m PyInstaller --onefile --noconsole --name "AI坤管理工具" {icon_arg} {data_arg} main.py'
    return run_cmd(cmd)

def build_portable():
    """创建便携版"""
    print("\n[4/5] 创建便携版...")
    
    portable_dir = PROJECT_DIR / "portable"
    if portable_dir.exists():
        shutil.rmtree(portable_dir)
    
    # 创建目录
    portable_dir.mkdir()
    (portable_dir / "ui").mkdir()
    
    # 复制文件
    files_to_copy = [
        ("main.py", "main.py"),
        ("ui/index.html", "ui/index.html"),
        ("ui/icon.ico", "ui/icon.ico"),
        ("requirements.txt", "requirements.txt"),
    ]
    
    for src, dst in files_to_copy:
        src_path = PROJECT_DIR / src
        dst_path = portable_dir / dst
        if src_path.exists():
            shutil.copy2(src_path, dst_path)
            print(f"  复制: {src}")
    
    # 创建启动脚本
    if PLATFORM == "Windows":
        create_windows_launcher(portable_dir)
    else:
        create_unix_launcher(portable_dir)
    
    # 创建 README
    create_readme(portable_dir)
    
    return True

def create_windows_launcher(portable_dir):
    """创建 Windows 启动脚本"""
    launcher_content = '''@echo off
chcp 65001 >nul
echo ========================================
echo   AI坤管理工具 - 便携版
echo ========================================
echo.
echo 正在启动...
echo.

:: 检查 Python
python --version >nul 2>&1
if errorlevel 1 (
    echo 未检测到 Python，正在下载便携版 Python...
    echo.
    
    :: 创建 python 目录
    if not exist python mkdir python
    
    :: 下载 Python 便携版
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip' -OutFile 'python\\python.zip'"
    powershell -Command "Expand-Archive -Path 'python\\python.zip' -DestinationPath 'python' -Force"
    del python\\python.zip
    
    :: 配置 Python
    echo import site >> python\\python311._pth
    
    echo Python 下载完成！
    echo.
    
    :: 使用便携版 Python
    set PYTHON_CMD=python\\python.exe
) else (
    set PYTHON_CMD=python
)

:: 安装依赖
echo 正在安装依赖...
%PYTHON_CMD% -m pip install pywebview requests --quiet --disable-pip-version-check

:: 启动应用
echo.
echo 启动 AI坤管理工具...
%PYTHON_CMD% main.py
pause
'''
    
    launcher_path = portable_dir / "启动.bat"
    launcher_path.write_text(launcher_content, encoding='utf-8')
    print("  创建: 启动.bat")

def create_unix_launcher(portable_dir):
    """创建 Unix 启动脚本"""
    launcher_content = '''#!/bin/bash
echo "========================================"
echo "  AI坤管理工具 - 便携版"
echo "========================================"
echo ""
echo "正在启动..."
echo ""

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo "未检测到 Python，正在安装..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install python@3.11
        else
            echo "请先安装 Homebrew: https://brew.sh"
            echo "然后运行: brew install python@3.11"
            exit 1
        fi
    else
        # Linux
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-tk
        elif command -v yum &> /dev/null; then
            sudo yum install -y python3 python3-pip python3-tkinter
        elif command -v pacman &> /dev/null; then
            sudo pacman -S python python-pip tk
        else
            echo "请手动安装 Python 3.11+"
            exit 1
        fi
    fi
fi

# 安装依赖
echo "正在安装依赖..."
python3 -m pip install pywebview requests --quiet --disable-pip-version-check

# 启动应用
echo ""
echo "启动 AI坤管理工具..."
python3 main.py
'''
    
    launcher_path = portable_dir / "启动.sh"
    launcher_path.write_text(launcher_content, encoding='utf-8')
    launcher_path.chmod(0o755)
    print("  创建: 启动.sh")

def create_readme(portable_dir):
    """创建 README"""
    readme_content = '''# AI坤管理工具 - 便携版

## 使用方法

### Windows
双击 `启动.bat` 即可运行

### macOS / Linux
```bash
chmod +x 启动.sh
./启动.sh
```

## 首次运行

首次运行会自动下载 Python 运行时和依赖包，请确保网络畅通。

## 功能

- 仪表盘：查看服务状态、余额
- 模型管理：启用/禁用模型
- 服务管理：启动/停止/重启 OpenClaw
- 配置备份：备份/恢复配置
- 运行诊断：检查服务状态
- 一键安装：安装 OpenClaw

## 注意事项

- 配置文件保存在用户目录下 (`~/.aikun-manager/`)
- 首次运行需要配置 API Key
- 需要 Node.js 环境才能使用 OpenClaw
- 余额信息需要登录后才能查看

## 系统要求

- Windows 10+ / macOS 10.15+ / Linux (主流发行版)
- Python 3.8+ (首次运行会自动安装)
- Node.js 18+ (使用 OpenClaw 需要)
'''
    
    readme_path = portable_dir / "README.md"
    readme_path.write_text(readme_content, encoding='utf-8')
    print("  创建: README.md")

def create_archive():
    """创建压缩包"""
    print("\n[5/5] 创建压缩包...")
    
    portable_dir = PROJECT_DIR / "portable"
    archive_name = "AI坤管理工具-Portable"
    
    if PLATFORM == "Windows":
        # 使用 PowerShell 创建 zip
        cmd = f'powershell -Command "Compress-Archive -Path \'{portable_dir}\\*\' -DestinationPath \'{PROJECT_DIR}\\{archive_name}.zip\' -Force"'
        return run_cmd(cmd)
    else:
        # 使用 zip 命令
        cmd = f'cd {portable_dir} && zip -r "{PROJECT_DIR}/{archive_name}.zip" .'
        return run_cmd(cmd)

def main():
    """主函数"""
    print("=" * 50)
    print("  AI坤管理工具 - 跨平台打包脚本")
    print("=" * 50)
    print(f"\n当前平台: {PLATFORM}")
    print(f"项目目录: {PROJECT_DIR}")
    
    # 执行打包流程
    clean_personal_data()
    
    if not install_dependencies():
        print("\n错误: 安装依赖失败")
        return 1
    
    if not build_exe():
        print("\n错误: 打包 exe 失败")
        return 1
    
    if not build_portable():
        print("\n错误: 创建便携版失败")
        return 1
    
    if not create_archive():
        print("\n错误: 创建压缩包失败")
        return 1
    
    print("\n" + "=" * 50)
    print("  打包完成！")
    print("=" * 50)
    print(f"\n  exe 文件: dist/AI坤管理工具{'.exe' if PLATFORM == 'Windows' else ''}")
    print(f"  便携版:   portable/")
    print(f"  压缩包:   AI坤管理工具-Portable.zip")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
