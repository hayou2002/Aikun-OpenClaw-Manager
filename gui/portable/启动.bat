@echo off
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
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip' -OutFile 'python\python.zip'"
    powershell -Command "Expand-Archive -Path 'python\python.zip' -DestinationPath 'python' -Force"
    del python\python.zip
    
    :: 配置 Python
    echo import site >> python\python311._pth
    
    echo Python 下载完成！
    echo.
    
    :: 使用便携版 Python
    set PYTHON_CMD=python\python.exe
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
