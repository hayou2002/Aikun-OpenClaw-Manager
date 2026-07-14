# AI坤 × OpenClaw 管理工具 - 打包说明

## 打包脚本

### Windows
```bash
build_windows.bat
```

### macOS / Linux
```bash
chmod +x build.sh
./build.sh
```

### Python 通用版
无需打包，直接运行 `run.bat` 或 `run.sh`

## 打包输出

| 平台 | 输出文件 | 说明 |
|------|---------|------|
| Windows | `dist/AI坤管理工具.exe` | 单文件，解压即用 |
| macOS | `dist/AI坤管理工具.app` | 应用包 |
| Linux | `dist/AI坤管理工具.AppImage` | 单文件，添加执行权限后运行 |
| Python | 直接运行 | 需要 Python 3.8+ |

## 注意事项

1. macOS 必须在 Mac 上打包
2. Linux 建议在较旧发行版上打包以保证兼容性
3. 打包前确保已安装所有依赖
