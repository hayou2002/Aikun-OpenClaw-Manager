@echo off
chcp 65001 >nul
echo ========================================
echo   AI坤管理工具 - Windows 打包脚本
echo ========================================
echo.

:: 清理旧的构建文件
echo [1/5] 清理旧文件...
if exist dist rmdir /s /q dist
if exist build rmdir /s /q build
if exist *.spec del /f *.spec
if exist __pycache__ rmdir /s /q __pycache__

:: 清理个人配置文件
echo [2/5] 清理个人配置...
if exist .aikun_cache.json del /f .aikun_cache.json
if exist .aikun_session.json del /f .aikun_session.json
if exist model_capabilities.json del /f model_capabilities.json

:: 安装依赖
echo [3/5] 检查依赖...
pip install pywebview requests pyinstaller --quiet

:: 打包 exe
echo [4/5] 打包 exe...
pyinstaller --onefile --noconsole --name "AI坤管理工具" --icon=ui/icon.ico --add-data="ui;ui" main.py

:: 创建便携版
echo [5/5] 创建便携版...
mkdir portable 2>nul
copy dist\AI坤管理工具.exe portable\
copy ui\index.html portable\ui\
copy ui\icon.ico portable\ui\
copy run.bat portable\
copy README.md portable\

echo.
echo ========================================
echo   打包完成！
echo ========================================
echo.
echo   exe 文件: dist\AI坤管理工具.exe
echo   便携版:   portable\
echo.
pause
