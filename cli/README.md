# AI坤 × OpenClaw 管理工具

管理群晖/Linux 上 Docker 部署的 OpenClaw，绑定 AI坤 API 作为唯一供应商。

## 版本说明

| 版本 | 平台 | 格式 | 说明 |
|------|------|------|------|
| CLI 脚本 | Linux/群晖/飞牛 | `aikun.sh` | 主版本，功能最全 |
| GUI Windows | Windows | `AI坤管理工具.exe` | 图形界面，双击即用 |
| GUI macOS | macOS | `AI坤管理工具.app` | 图形界面，拖到应用程序 |

### CLI 脚本（推荐）

功能最全，适合服务器管理：

| 功能 | 说明 |
|------|------|
| 🚀 首次初始化 | 引导配置 API Key → 拉取模型 → 选择启用 → 写入配置 |
| 📋 模型管理 | 刷新模型列表、切换默认模型、手动添加/禁用模型、编辑模型参数（上下文长度/最大输出） |
| 🔧 服务管理 | 启动/停止/重启 OpenClaw、查看运行状态和日志 |
| 💾 配置与备份 | 查看配置、更新 Key、一键备份/恢复、更新模型参数 |
| 🩺 环境诊断 | 检测依赖、Docker、容器、端口、API 连通性，自动修复，一键安装 OpenClaw |
| 📖 使用网址 | 显示 API 地址、管理界面地址、Token、curl 示例 |

### GUI 版本

图形界面，适合本地使用：

| 功能 | 说明 |
|------|------|
| 📊 仪表盘 | 服务状态、端口、API 连通性 |
| 📋 模型管理 | 勾选启用/禁用、设置默认、添加自定义 |
| ⚙️ 服务控制 | 启动/停止/重启 |
| 💾 备份恢复 | 一键备份/恢复 |
| 📖 使用网址 | 复制 API/管理界面地址 |

## 一键安装（CLI 脚本）

复制下面整段命令，在群晖终端（或 Linux SSH）中粘贴执行：

```bash
# 方式一：curl 直接下载并安装（飞牛/群晖 先 sudo -i 提权）
sudo -i -c 'curl -fsSL https://raw.githubusercontent.com/hayou2002/aikun-manager/main/aikun.sh -o /tmp/aikun.sh && bash /tmp/aikun.sh --install && rm -f /tmp/aikun.sh'
```

```bash
# 方式二：wget（群晖默认没有 curl 时可用）
sudo -i -c 'wget -qO /tmp/aikun.sh https://raw.githubusercontent.com/hayou2002/aikun-manager/main/aikun.sh && bash /tmp/aikun.sh --install && rm -f /tmp/aikun.sh'
```

安装完成后，任意路径输入 `aikun` 即可启动。

## GUI 版本下载

从 [GitHub Releases](https://github.com/hayou2002/aikun-manager/releases) 下载：

| 平台 | 文件 | 说明 |
|------|------|------|
| Windows | `AI坤管理工具.exe` | 双击运行，无需安装 |
| macOS | `AI坤管理工具.app` | 拖到应用程序文件夹 |

> GUI 版本通过 GitHub Actions 自动打包，支持 Windows、macOS、Linux 三平台。

## 安装过程（CLI 脚本）

`--install` 模式会自动完成：

1. **检测群晖 DSM** → 自动安装缺失依赖（curl / python3）
2. **复制脚本** → `/usr/local/bin/aikun`，权限 755，属主 root
3. **检测 OpenClaw 容器** → 给出部署建议

```
╔══════════════════════════════════════════╗
║   AI坤 × OpenClaw 管理工具 安装程序     ║
╚══════════════════════════════════════════╝

[1/4] 检查运行权限         ✅ root
[2/4] 检查依赖             ✅ curl / python3 / bash
[3/4] 安装脚本             ✅ /usr/local/bin/aikun
[4/4] 检查 OpenClaw        ✅ Docker 容器运行中

安装完成！输入 aikun 启动管理工具
```

## 使用方法

### ⚡ 提权（飞牛/群晖 必读）

飞牛 OS 和群晖 DSM 默认限制普通用户的 Docker 及系统操作权限。
运行管理脚本前，**必须先提权到 root**：

```bash
# SSH 登录后，先切换到 root
sudo -i

# 然后运行管理工具
aikun
```

> 飞牛 OS 默认密码与 Web 端一致，群晖 admin 用户需在「控制面板 → 终端机」中启用 SSH。

也支持一行命令：

```bash
sudo -i -c aikun
```

### 启动

```bash
# 已 sudo -i 提权后直接运行
aikun

# 未提权时
sudo -i -c aikun
```

### 首次使用

1. 启动后自动进入初始化引导
2. 输入 AI坤 API Key（从 [aikun.cnzc.qzz.io](https://aikun.cnzc.qzz.io) 获取）
3. 自动测试连通性
4. 从可用模型列表中选择要启用的模型（多选用空格分隔）
5. 配置每个模型的上下文长度和最大输出（支持统一设置或逐个设置）
6. 选择默认模型
7. 确认写入并重启 OpenClaw

### 日常使用

```bash
# 已提权
aikun

# 未提权
sudo -i -c aikun
```

菜单操作：

```
  ┌──────────────────────────────────┐
  │  1) 📋 模型管理                  │
  │  2) 🔧 服务管理                  │
  │  3) 💾 配置与备份                │
  │  4) 🩺 环境诊断                  │
  │  5) 📖 查看使用网址              │
  │  0) ❌ 退出                      │
  └──────────────────────────────────┘
```

## 模型参数管理

脚本会自动获取模型的上下文长度（contextWindow）和最大输出（maxTokens）：

| 获取方式 | 说明 |
|----------|------|
| GitHub 远程获取 | GPT、Claude、Gemini、Grok 等国际模型，数据来自 [truefoundry/models](https://github.com/truefoundry/models) |
| 内置知识库 | DeepSeek、Kimi、Qwen、MiniMax、GLM、豆包等国内模型 |
| 手动设置 | 用户可在模型管理中手动编辑每个模型的参数 |

### 更新已有配置的模型参数

```
aikun → 配置与备份 → 更新模型参数
```

一键修正所有已启用模型的上下文长度和最大输出，无需重新选择模型。

### 查看当前配置

```
aikun → 配置与备份 → 查看当前配置
```

显示每个模型的 ctx（上下文）和 out（最大输出）信息。

## 环境诊断

运行 `aikun → 环境诊断`，脚本会自动检测：

- 依赖检查（curl、python3、jq）
- Docker 状态
- OpenClaw 容器状态
- 端口连通性（18790）
- AI坤 API 连通性

### 自动修复

| 问题 | 修复操作 |
|------|----------|
| OpenClaw 未安装 | 提供安装选项：官方版 / 汉化版 |
| OpenClaw 容器已停止 | 自动启动容器 |
| jq 未安装 | 自动安装 |

### 安装 OpenClaw

如果检测到 OpenClaw 未安装，脚本会提供两个版本选择：

1. **官方版** (`openclaw/openclaw:latest`)
2. **汉化版** (`1186258278/openclaw-zh:latest`) — 来自 [OpenClawChineseTranslation](https://github.com/1186258278/OpenClawChineseTranslation)

选择后自动拉取镜像、创建容器、启动服务。

## 前置要求

| 依赖 | 必需 | 说明 |
|------|------|------|
| Docker | ✅ | OpenClaw 运行环境 |
| curl | ✅ | API 通信（群晖自带） |
| python3 | ✅ | JSON 处理（群晖自带） |
| bash | ✅ | 脚本运行环境 |

### OpenClaw Docker 部署（如未安装）

```bash
# 拉取镜像
docker pull openclaw/openclaw:latest

# 创建并启动容器
docker run -d \
  --name openclaw \
  --restart unless-stopped \
  -p 18790:18790 \
  -e OPENCLAW_GATEWAY_TOKEN=你的访问令牌 \
  openclaw/openclaw:latest \
  --allow-unconfigured --port 18790
```

部署完成后运行 `sudo aikun` 进入初始化。

## 常见问题

### Q: 提示"权限不足"

飞牛/群晖必须先提权：
```bash
sudo -i
aikun
```

### Q: 提示"未找到 OpenClaw 容器"

先部署 OpenClaw Docker（见上方前置要求），或在诊断菜单中选择安装 OpenClaw。

### Q: 模型列表拉取失败

检查 API Key 是否正确，网络是否能访问 `aikun.cnzc.qzz.io`。

### Q: 容器启动后又退出

运行 `aikun` → 环境诊断，检查配置是否有误。常见原因是模型配置缺少字段，脚本已自动处理。

### Q: 群晖没有 curl

```bash
# 通过套件中心安装，或：
opkg install curl    # 如果有 entwear
```

### Q: 模型上下文长度不对

运行 `aikun` → 配置与备份 → 更新模型参数，一键修正所有模型的上下文长度和最大输出。

## 更新脚本

```bash
sudo -i -c 'curl -fsSL https://raw.githubusercontent.com/hayou2002/aikun-manager/main/aikun.sh -o /tmp/aikun.sh && bash /tmp/aikun.sh --install && rm -f /tmp/aikun.sh'
```

## 卸载

```bash
sudo rm -f /usr/local/bin/aikun
sudo rm -rf ~/.aikun-manager
```

## 文件位置

### CLI 脚本（Linux/群晖/飞牛）

| 路径 | 说明 |
|------|------|
| `/usr/local/bin/aikun` | 脚本主体 |
| `~/.aikun-manager/` | 缓存目录（API Key、备份等） |
| 容器内 `/home/node/.openclaw/openclaw.json` | OpenClaw 配置 |

### GUI 版本（Windows/macOS）

| 路径 | 说明 |
|------|------|
| `AI坤管理工具.exe` / `AI坤管理工具.app` | 主程序，双击运行 |
| 同目录 `aikun-config.json` | 缓存的 API Key |
| 容器内 `/home/node/.openclaw/openclaw.json` | OpenClaw 配置 |

## 打包说明

CLI 脚本无需打包，直接使用。

GUI 版本通过 GitHub Actions 自动打包：

```bash
# 打包 Windows 版
build_windows.bat

# 打包 Linux/macOS 版
bash build.sh
```

打包后文件在 `dist/` 目录。

## License

Private - All rights reserved.
