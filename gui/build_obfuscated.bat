@echo off
chcp 65001 >nul
echo ========================================
echo   AI坤 × OpenClaw 管理工具 - 代码混淆打包
echo ========================================
echo.

:: 检查 pyarmor
echo [1/5] 检查混淆工具...
pyarmor --version >nul 2>&1
if errorlevel 1 (
    echo pyarmor 未安装，正在安装...
    pip install pyarmor -q
)

:: 清理
echo [2/5] 清理旧文件...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist obfuscated rmdir /s /q obfuscated

:: 混淆代码
echo [3/5] 正在混淆代码...
pyarmor gen -O obfuscated -i main.py ui/ model_capabilities.json 2>&1

:: 打包混淆后的代码
echo [4/5] 正在打包混淆后的代码...
cd obfuscated
pyinstaller --onefile --noconsole --name "AI坤管理工具" ^
    --add-data "ui;ui" ^
    --add-data "model_capabilities.json;." ^
    --icon "../ui/icon.ico" ^
    --clean --noconfirm ^
    main.py 2>&1

:: 移动到 dist
echo [5/5] 完成...
cd ..
if exist "obfuscated\dist\AI坤管理工具.exe" (
    move "obfuscated\dist\AI坤管理工具.exe" "dist\" >nul
    echo.
    echo ========================================
    echo   混淆打包成功！
    echo   输出文件: dist\AI坤管理工具.exe
    echo ========================================
    explorer dist
) else (
    echo   打包失败
)

pause
