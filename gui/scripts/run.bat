@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ========================================
echo   AI坤管理工具 - 启动
echo ========================================
echo.

set SCRIPT_DIR=%~dp0
set APP_DIR=%SCRIPT_DIR%app
set PYTHON_DIR=%SCRIPT_DIR%python
set PYTHON_VERSION=3.12.4

:: 查找 Python
set PYTHON_CMD=

:: 优先使用便携版
if exist "%PYTHON_DIR%\python.exe" (
    set "PYTHON_CMD=%PYTHON_DIR%\python.exe"
    goto :found_python
)

:: 尝试系统 Python
where python >nul 2>&1
if %errorlevel%==0 (
    set "PYTHON_CMD=python"
    goto :found_python
)

where python3 >nul 2>&1
if %errorlevel%==0 (
    set "PYTHON_CMD=python3"
    goto :found_python
)

:: 未找到 Python，下载便携版
echo [提示] 未检测到 Python，正在下载便携版...
echo.

mkdir "%PYTHON_DIR%" 2>nul

:: 下载 Python 嵌入式版本
set PYTHON_URL=https://www.python.org/ftp/python/%PYTHON_VERSION%/python-%PYTHON_VERSION%-embed-amd64.zip
set PIP_URL=https://bootstrap.pypa.io/get-pip.py

echo [1/4] 下载 Python %PYTHON_VERSION%...
curl -L -o "%PYTHON_DIR%\python-embed.zip" "%PYTHON_URL%" 2>&1
if errorlevel 1 (
    echo 下载失败，请检查网络连接
    pause
    exit /b 1
)

echo [2/4] 解压 Python...
powershell -Command "Expand-Archive -Path '%PYTHON_DIR%\python-embed.zip' -DestinationPath '%PYTHON_DIR%' -Force"
del "%PYTHON_DIR%\python-embed.zip"

:: 启用 pip
echo [3/4] 配置 Python...
for %%f in (%PYTHON_DIR%\*._pth) do (
    powershell -Command "(Get-Content '%%f') -replace '#import site','import site' | Set-Content '%%f'"
)

:: 安装 pip
echo [4/4] 安装 pip...
curl -L -o "%PYTHON_DIR%\get-pip.py" "%PIP_URL%" 2>&1
"%PYTHON_DIR%\python.exe" "%PYTHON_DIR%\get-pip.py" --no-warn-script-location 2>&1
del "%PYTHON_DIR%\get-pip.py"

set "PYTHON_CMD=%PYTHON_DIR%\python.exe"
echo.
echo Python 便携版安装完成！

:found_python
echo Python: %PYTHON_CMD%

:: 检查依赖
echo 检查依赖...
%PYTHON_CMD% -c "import webview" >nul 2>&1
if errorlevel 1 (
    echo 安装依赖...
    if exist "%SCRIPT_DIR%requirements.txt" (
        %PYTHON_CMD% -m pip install -r "%SCRIPT_DIR%requirements.txt" -q 2>nul
    ) else (
        %PYTHON_CMD% -m pip install pywebview requests pillow -q
    )
)

:: 启动程序
echo.
echo 启动 AI坤管理工具...
cd /d "%APP_DIR%"
%PYTHON_CMD% main.py

pause
