@echo off
chcp 65001 >nul
echo ========================================
echo   AI坤管理工具 - 便携版打包脚本
echo ========================================
echo.

:: 清理旧文件
echo [1/6] 清理旧文件...
if exist portable rmdir /s /q portable
if exist AI坤管理工具-Portable.zip del /f AI坤管理工具-Portable.zip

:: 清理个人配置
echo [2/6] 清理个人配置...
if exist .aikun_cache.json del /f .aikun_cache.json
if exist .aikun_session.json del /f .aikun_session.json

:: 创建目录结构
echo [3/6] 创建目录结构...
mkdir portable
mkdir portable\ui
mkdir portable\python

:: 复制应用文件
echo [4/6] 复制应用文件...
copy main.py portable\
copy ui\index.html portable\ui\
copy ui\icon.ico portable\ui\
copy requirements.txt portable\

:: 创建启动脚本
echo [5/6] 创建启动脚本...

:: Windows 启动脚本
(
echo @echo off
echo chcp 65001 ^>nul
echo echo 正在启动 AI坤管理工具...
echo echo.
echo echo 首次运行会自动下载 Python 运行时，请稍候...
echo echo.
echo.
echo :: 检查 Python 是否可用
echo python --version ^>nul 2^>^&1
echo if errorlevel 1 ^(
echo     echo 未检测到 Python，正在下载便携版 Python...
echo     echo.
echo     :: 下载 Python 便携版
echo     powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip' -OutFile 'python\python.zip'"
echo     powershell -Command "Expand-Archive -Path 'python\python.zip' -DestinationPath 'python' -Force"
echo     del python\python.zip
echo     echo Python 下载完成！
echo     echo.
echo ^)
echo.
echo :: 安装依赖
echo echo 正在安装依赖...
echo python -m pip install pywebview requests --quiet --disable-pip-version-check
echo.
echo :: 启动应用
echo echo 启动 AI坤管理工具...
echo python main.py
echo pause
) > portable\启动.bat

:: macOS/Linux 启动脚本
(
echo #!/bin/bash
echo echo "正在启动 AI坤管理工具..."
echo echo ""
echo echo "首次运行会自动下载 Python 运行时，请稍候..."
echo echo ""
echo.
echo # 检查 Python 是否可用
echo if ! command -v python3 ^&^> /dev/null; then
echo     echo "未检测到 Python，正在安装..."
echo     if [[ "$OSTYPE" == "darwin"* ]]; then
echo         # macOS
echo         if command -v brew ^&^> /dev/null; then
echo             brew install python@3.11
echo         else
echo             echo "请先安装 Homebrew: https://brew.sh"
echo             exit 1
echo         fi
echo     else
echo         # Linux
echo         if command -v apt-get ^&^> /dev/null; then
echo             sudo apt-get update ^&^& sudo apt-get install -y python3 python3-pip python3-tk
echo         elif command -v yum ^&^> /dev/null; then
echo             sudo yum install -y python3 python3-pip python3-tkinter
echo         else
echo             echo "请手动安装 Python 3.11+"
echo             exit 1
echo         fi
echo     fi
echo fi
echo.
echo # 安装依赖
echo echo "正在安装依赖..."
echo python3 -m pip install pywebview requests --quiet --disable-pip-version-check
echo.
echo # 启动应用
echo echo "启动 AI坤管理工具..."
echo python3 main.py
) > portable\启动.sh
chmod +x portable\启动.sh

:: 创建 README
echo [6/6] 创建说明文件...
(
echo # AI坤管理工具 - 便携版
echo.
echo ## 使用方法
echo.
echo ### Windows
echo 双击 `启动.bat` 即可运行
echo.
echo ### macOS / Linux
echo ```bash
echo chmod +x 启动.sh
echo ./启动.sh
echo ```
echo.
echo ## 首次运行
echo.
echo 首次运行会自动下载 Python 运行时和依赖包，请确保网络畅通。
echo.
echo ## 功能
echo.
echo - 仪表盘：查看服务状态、余额
echo - 模型管理：启用/禁用模型
echo - 服务管理：启动/停止/重启 OpenClaw
echo - 配置备份：备份/恢复配置
echo - 运行诊断：检查服务状态
echo - 一键安装：安装 OpenClaw
echo.
echo ## 注意事项
echo.
echo - 配置文件保存在用户目录下，不会打包进程序
echo - 首次运行需要配置 API Key
echo - 需要 Node.js 环境才能使用 OpenClaw
) > portable\README.md

:: 打包
echo.
echo 正在打包...
powershell -Command "Compress-Archive -Path 'portable\*' -DestinationPath 'AI坤管理工具-Portable.zip' -Force"

echo.
echo ========================================
echo   打包完成！
echo ========================================
echo.
echo   便携版目录: portable\
echo   压缩包:     AI坤管理工具-Portable.zip
echo.
pause
