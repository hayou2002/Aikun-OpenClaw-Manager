# AI坤 × OpenClaw 管理工具

## 打包说明

### Windows 打包

```bash
# 方式一：普通打包
build_windows.bat

# 方式二：混淆打包（推荐）
build_obfuscated.bat
```

输出文件：`dist/AI坤管理工具.exe`

### Linux 打包

```bash
chmod +x build.sh
./build.sh
```

输出文件：`dist/AI坤管理工具`

### macOS 打包

**需要在 Mac 上执行：**

```bash
# 1. 安装依赖
pip3 install pywebview pyinstaller

# 2. 执行打包
chmod +x build.sh
./build.sh
```

输出文件：`dist/AI坤管理工具.app`

---

## 打包配置

### 单文件模式
- 使用 `--onefile` 参数，所有依赖打包进单个可执行文件
- 运行时自动解压到临时目录，退出后清理
- 用户看不到额外的文件夹和文件

### 图标
- Windows: `ui/icon.ico`
- macOS/Linux: `ui/icon.png`

### 代码混淆
使用 `pyarmor` 进行代码混淆，防止源码被直接查看：
- 混淆字节码
- 变量名混淆
- 字符串加密

---

## 注意事项

1. **macOS 打包必须在 Mac 上进行**，无法跨平台编译
2. **Windows 打包会生成较大的 .exe**（约 30-50MB），因为包含 Python 运行时
3. **Linux 打包需要 glibc 兼容性**，建议在较旧的发行版上打包以保证兼容性
4. **代码混淆不能 100% 防止反编译**，但能显著提高破解门槛

## 文件结构

```
aikun-gui/
├── main.py              # 主程序
├── ui/
│   ├── index.html       # 前端界面
│   ├── icon.png         # 程序图标
│   └── icon.ico         # Windows 图标
├── model_capabilities.json  # 模型能力数据
├── build.spec           # PyInstaller 配置
├── build_windows.bat    # Windows 打包脚本
├── build.sh             # Linux/macOS 打包脚本
├── build_obfuscated.bat # 混淆打包脚本
└── dist/                # 打包输出目录
    └── AI坤管理工具.exe  # Windows 可执行文件
```
