# AI坤 × OpenClaw 管理工具

跨平台 OpenClaw 管理工具，支持 Windows / macOS / Linux。

## 📁 项目结构

```
aikun-gui/
├── main.py              # 主程序
├── requirements.txt     # Python 依赖
├── README.md           # 项目说明
│
├── ui/                  # 前端界面
│   ├── index.html      # 主页面
│   ├── icon.ico        # 图标 (Windows)
│   └── icon.png        # 图标 (通用)
│
├── scripts/             # 构建脚本
│   ├── build.bat       # Windows 打包
│   ├── build_all.py    # 跨平台打包
│   ├── build_portable.bat  # 便携版打包
│   ├── run.bat         # Windows 启动
│   └── run.sh          # macOS/Linux 启动
│
├── docs/                # 文档
│   ├── PACKAGING.md    # 打包说明
│   └── 项目索引.md      # 项目索引
│
├── release/             # 发布文件
│   ├── AI坤管理工具.exe          # Windows 单文件
│   ├── AI坤管理工具-Windows.zip  # Windows 压缩包
│   ├── AI坤管理工具-Portable.zip # 便携版
│   └── AI坤管理工具-Python.zip   # Python 版
│
└── portable/            # 便携版源文件
    ├── main.py
    ├── README.md
    ├── requirements.txt
    ├── 启动.bat
    └── ui/
```

## 🚀 快速开始

### Windows (exe)
双击 `release/AI坤管理工具.exe` 直接运行

### 便携版 (无需安装 Python)
1. 解压 `release/AI坤管理工具-Portable.zip`
2. 双击 `启动.bat`
3. 首次运行会自动下载 Python 运行时

### 从源码运行
```bash
pip install -r requirements.txt
python main.py
```

## 🔧 功能特性

- **仪表盘**: 查看服务状态、余额
- **模型管理**: 启用/禁用模型、设置默认模型
- **服务管理**: 启动/停止/重启 OpenClaw
- **配置备份**: 备份/恢复配置
- **运行诊断**: 检查服务状态、一键修复
- **一键安装**: 安装 OpenClaw (原版/中文版)

## 📦 打包

### Windows exe
```bash
cd scripts
build.bat
```

### 便携版
```bash
cd scripts
build_portable.bat
```

### 跨平台打包
```bash
cd scripts
python build_all.py
```

## 📝 注意事项

- 配置文件保存在 `~/.aikun-manager/`，不会打包进程序
- 首次运行需要配置 API Key
- 需要 Node.js 环境才能使用 OpenClaw
- 余额信息需要登录后才能查看

## 📄 许可证

MIT License
