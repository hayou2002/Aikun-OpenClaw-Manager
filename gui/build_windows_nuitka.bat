@echo off
chcp 65001 >nul
echo ========================================
echo   AI坤 × OpenClaw 管理工具 - Windows 打包 (Nuitka)
echo ========================================
echo.

:: 检查 Nuitka
echo [1/5] 检查 Nuitka...
python -m nuitka --version >nul 2>&1
if errorlevel 1 (
    echo Nuitka 未安装，正在安装...
    pip install nuitka -q
)

:: 检查 ordered-set (Nuitka 加速依赖)
python -c "import orderedset" >nul 2>&1
if errorlevel 1 (
    echo 安装加速依赖...
    pip install ordered-set -q
)

:: 清理旧构建
echo [2/5] 清理旧构建...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist main.build rmdir /s /q main.build
if exist main.dist rmdir /s /q main.dist
if exist main.onefile-build rmdir /s /q main.onefile-build

:: 混淆代码（可选）
echo [3/5] 混淆代码...
pyarmor gen -O obfuscated -i main.py -i ui/ -i model_capabilities.json 2>nul
if errorlevel 1 (
    echo 混淆跳过，直接打包原代码
    copy main.py main_build.py >nul
) else (
    copy obfuscated\main.py main_build.py >nul
)

:: 使用 Nuitka 打包
echo [4/5] 正在打包（首次可能需要 5-10 分钟）...
python -m nuitka ^
    --onefile ^
    --windows-disable-console ^
    --windows-icon-from-ico=ui/icon.ico ^
    --include-data-file=ui/index.html=ui/index.html ^
    --include-data-file=ui/icon.png=ui/icon.png ^
    --include-data-file=model_capabilities.json=model_capabilities.json ^
    --output-filename="AI坤管理工具.exe" ^
    --product-name="AI坤管理工具" ^
    --file-version=1.0.0 ^
    --product-version=1.0.0 ^
    --company-name="AI坤" ^
    --file-description="AI坤 × OpenClaw 管理工具" ^
    --nofollow-import-to=tkinter ^
    --nofollow-import-to=unittest ^
    --nofollow-import-to=test ^
    --assume-yes-for-downloads ^
    main_build.py 2>&1

:: 清理临时文件
echo [5/5] 清理临时文件...
if exist main_build.py del main_build.py
if exist main.build rmdir /s /q main.build
if exist main.dist rmdir /s /q main.dist
if exist main.onefile-build rmdir /s /q main.onefile-build
if exist obfuscated rmdir /s /q obfuscated

:: 检查结果
if exist "AI坤管理工具.exe" (
    if not exist dist mkdir dist
    move "AI坤管理工具.exe" "dist\" >nul
    echo.
    echo ========================================
    echo   打包成功！
    echo   输出文件: dist\AI坤管理工具.exe
    echo ========================================
    
    for %%A in ("dist\AI坤管理工具.exe") do (
        set size=%%~zA
        set /a sizeMB=!size! / 1048576
        echo   文件大小: !sizeMB! MB
    )
    
    explorer dist
) else (
    echo.
    echo   打包失败，请检查错误信息
    echo.
)

pause
