@echo off
chcp 65001 >nul
echo ========================================
echo   AI坤 × OpenClaw 管理工具 - 全平台打包
echo ========================================
echo.

:: 设置变量
set VERSION=1.0.0
set RELEASE_DIR=release
set DIST_DIR=dist

:: 清理旧文件
echo [1/6] 清理旧文件...
if exist %RELEASE_DIR% rmdir /s /q %RELEASE_DIR%
if exist %DIST_DIR% rmdir /s /q %DIST_DIR%
if exist build rmdir /s /q build
mkdir %RELEASE_DIR%

:: 打包 Windows 版
echo [2/6] 打包 Windows 版...
pyinstaller build.spec --clean --noconfirm 2>&1
if exist "%DIST_DIR%\AI坤管理工具.exe" (
    echo   ✅ Windows 打包成功
    copy "%DIST_DIR%\AI坤管理工具.exe" "%RELEASE_DIR%\" >nul
) else (
    echo   ❌ Windows 打包失败
)

:: 创建 Python 通用版
echo [3/6] 创建 Python 通用版...
set PYTHON_DIR=AI坤管理工具-Python
if exist %PYTHON_DIR% rmdir /s /q %PYTHON_DIR%
mkdir %PYTHON_DIR%
mkdir %PYTHON_DIR%\ui

copy main.py "%PYTHON_DIR%\" >nul
copy model_capabilities.json "%PYTHON_DIR%\" >nul
copy requirements.txt "%PYTHON_DIR%\" >nul
copy run.bat "%PYTHON_DIR%\" >nul
copy run.sh "%PYTHON_DIR%\" >nul
copy README.md "%PYTHON_DIR%\" >nul
copy ui\index.html "%PYTHON_DIR%\ui\" >nul
copy ui\icon.png "%PYTHON_DIR%\ui\" >nul
copy ui\icon.ico "%PYTHON_DIR%\ui\" >nul

Compress-Archive -Path "%PYTHON_DIR%\*" -DestinationPath "%RELEASE_DIR%\AI坤管理工具-Python.zip" -Force
rmdir /s /q %PYTHON_DIR%
echo   ✅ Python 通用版创建完成

:: 创建 Release 说明
echo [4/6] 创建 Release 说明...
(
echo ## AI坤 × OpenClaw 管理工具 v%VERSION%
echo.
echo ### 📥 下载
echo.
echo #### Windows ^（推荐^）
echo - 下载：`AI坤管理工具.exe`
echo - 双击即可运行
echo - 系统要求：Windows 10/11 64位
echo.
echo #### Python 通用版 ^（所有平台^）
echo - 下载：`AI坤管理工具-Python.zip`
echo - 需要已安装 Python 3.8+
echo - Windows 双击 `run.bat` 启动
echo - macOS/Linux 执行 `./run.sh` 启动
echo.
echo ### ⚠️ 注意事项
echo - 首次使用请先配置 API Key
echo - 详细说明请参考 README.md
) > %RELEASE_DIR%\RELEASE_NOTES.md

:: 显示打包结果
echo [5/6] 打包结果：
echo.
dir /b %RELEASE_DIR%
echo.

:: 计算文件大小
echo [6/6] 文件大小：
for %%f in (%RELEASE_DIR%\*) do (
    set size=%%~zf
    set /a sizeMB=!size! / 1048576
    echo   %%f: !sizeMB! MB
)

echo.
echo ========================================
echo   打包完成！
echo   输出目录: %RELEASE_DIR%
echo ========================================
echo.
echo 下一步：
echo 1. 将 %RELEASE_DIR% 中的文件上传到 GitHub Releases
echo 2. 或运行 upload_release.bat 自动上传
echo.

pause
