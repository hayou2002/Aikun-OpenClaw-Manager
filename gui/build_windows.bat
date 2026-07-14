@echo off
chcp 65001 >nul
echo ========================================
echo   AI坤 × OpenClaw 管理工具 - Windows 打包
echo ========================================
echo.

:: 检查依赖
echo [1/4] 检查依赖...
python -c "import pywebview; import PyInstaller" 2>nul
if errorlevel 1 (
    echo 缺少依赖，正在安装...
    pip install pywebview pyinstaller -q
)

:: 清理旧构建
echo [2/4] 清理旧构建...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist

:: 打包
echo [3/4] 正在打包（可能需要 2-5 分钟）...
pyinstaller build.spec --clean --noconfirm 2>&1

:: 检查结果
echo [4/4] 检查打包结果...
if exist "dist\AI坤管理工具.exe" (
    echo.
    echo ========================================
    echo   打包成功！
    echo   输出文件: dist\AI坤管理工具.exe
    echo ========================================
    echo.
    
    :: 显示文件大小
    for %%A in ("dist\AI坤管理工具.exe") do (
        set size=%%~zA
        set /a sizeMB=!size! / 1048576
        echo   文件大小: !sizeMB! MB
    )
    
    :: 打开输出目录
    explorer dist
) else (
    echo.
    echo   打包失败，请检查错误信息
    echo.
)

pause
