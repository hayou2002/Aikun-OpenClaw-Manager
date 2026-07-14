# AI坤管理工具 - 便携版

## 使用方法

### Windows
双击 `启动.bat` 即可运行

### macOS / Linux
```bash
chmod +x 启动.sh
./启动.sh
```

## 首次运行

首次运行会自动下载 Python 运行时和依赖包，请确保网络畅通。

## 功能

- 仪表盘：查看服务状态、余额
- 模型管理：启用/禁用模型
- 服务管理：启动/停止/重启 OpenClaw
- 配置备份：备份/恢复配置
- 运行诊断：检查服务状态
- 一键安装：安装 OpenClaw

## 注意事项

- 配置文件保存在用户目录下 (`~/.aikun-manager/`)
- 首次运行需要配置 API Key
- 需要 Node.js 环境才能使用 OpenClaw
- 余额信息需要登录后才能查看

## 系统要求

- Windows 10+ / macOS 10.15+ / Linux (主流发行版)
- Python 3.8+ (首次运行会自动安装)
- Node.js 18+ (使用 OpenClaw 需要)
