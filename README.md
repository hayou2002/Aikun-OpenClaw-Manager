# Aikun-OpenClaw-Manager

AI坤 × OpenClaw 管理工具 - CLI脚本 + GUI图形界面

## 项目结构

```
Aikun-OpenClaw-Manager/
├── cli/                    # CLI 脚本（Linux/群晖/飞牛）
│   ├── aikun.sh           # 主脚本
│   └── README.md          # CLI 文档
├── gui/                    # GUI 版本（Windows/macOS/Linux）
│   ├── main.py            # 主程序
│   ├── build.sh           # Linux/macOS 打包脚本
│   ├── build_windows.bat  # Windows 打包脚本
│   └── ...
├── releases/               # 预编译发布包
│   ├── AI坤管理工具.exe    # Windows 版
│   ├── AI坤管理工具.app    # macOS 版（GitHub Actions 自动打包）
│   └── ...
└── README.md               # 本文件
```

## 版本说明

| 版本 | 平台 | 格式 | 说明 |
|------|------|------|------|
| CLI 脚本 | Linux/群晖/飞牛 | `aikun.sh` | 主版本，功能最全 |
| GUI Windows | Windows | `AI坤管理工具.exe` | 图形界面，双击即用 |
| GUI macOS | macOS | `AI坤管理工具.app` | 图形界面，拖到应用程序 |

## 快速开始

### CLI 脚本（推荐服务器使用）

```bash
# 一键安装（飞牛/群晖 先 sudo -i 提权）
sudo -i -c 'curl -fsSL https://raw.githubusercontent.com/hayou2002/Aikun-OpenClaw-Manager/main/cli/aikun.sh -o /tmp/aikun.sh && bash /tmp/aikun.sh --install && rm -f /tmp/aikun.sh'
```

安装完成后，任意路径输入 `aikun` 即可启动。

### GUI 版本（推荐本地使用）

从 [GitHub Releases](https://github.com/hayou2002/Aikun-OpenClaw-Manager/releases) 下载对应平台版本：

| 平台 | 文件 | 说明 |
|------|------|------|
| Windows | `AI坤管理工具.exe` | 双击运行，无需安装 |
| macOS | `AI坤管理工具.app` | 拖到应用程序文件夹 |

## 功能对比

| 功能 | CLI | GUI |
|------|-----|-----|
| 首次初始化 | ✅ | ✅ |
| 模型管理 | ✅ | ✅ |
| 服务管理 | ✅ | ✅ |
| 配置备份 | ✅ | ✅ |
| 环境诊断 | ✅ | ✅ |
| 安装 OpenClaw | ✅ | ❌ |
| 模型参数管理 | ✅ | ❌ |
| 查看使用网址 | ✅ | ✅ |

## 打包说明

### CLI 脚本

无需打包，直接使用。

### GUI 版本

#### Windows

```bash
cd gui
build_windows.bat
```

#### Linux/macOS

```bash
cd gui
bash build.sh
```

#### GitHub Actions 自动打包

打 tag 自动触发三平台打包：

```bash
git tag v1.0.0
git push --tags
```

GitHub Actions 会自动：
1. 在 Windows runner 上打包 `.exe`
2. 在 macOS runner 上打包 `.app`
3. 在 Linux runner 上打包二进制
4. 创建 Release 并上传三个文件

## 常见问题

### Q: CLI 脚本安装失败

检查是否有 root 权限：
```bash
sudo -i
aikun
```

### Q: GUI 版本无法启动

Windows：确保已安装 Visual C++ Redistributable
macOS：在系统偏好设置中允许运行未签名应用

### Q: 如何更新 CLI 脚本

重新执行安装命令即可：
```bash
sudo -i -c 'curl -fsSL https://raw.githubusercontent.com/hayou2002/Aikun-OpenClaw-Manager/main/cli/aikun.sh -o /tmp/aikun.sh && bash /tmp/aikun.sh --install && rm -f /tmp/aikun.sh'
```

## License

Private - All rights reserved.
