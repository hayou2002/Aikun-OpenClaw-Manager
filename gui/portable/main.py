"""
AI坤 × OpenClaw 管理工具 - GUI 版
跨平台支持: Windows / macOS / Linux（含群晖 Docker）
"""

import json
import os
import platform
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import webbrowser
import webview
import requests
from pathlib import Path

# ============================================================
#  常量
# ============================================================

AIKUN_BASE = "https://aikun.cnzc.qzz.io/v1"
AIKUN_SITE = "https://aikun.cnzc.qzz.io"
CACHE_DIR = Path.home() / ".aikun-manager"
CACHE_FILE = CACHE_DIR / "cache.json"
BACKUP_DIR = CACHE_DIR / "backups"
PLATFORM = platform.system()  # 'Windows' / 'Darwin' / 'Linux'

# 模型能力数据库路径
MODEL_CAPS_FILE = Path(__file__).parent / "model_capabilities.json"

# New-API Session 存储
SESSION_FILE = CACHE_DIR / "aikun_session.json"

# ============================================================
#  平台检测
# ============================================================

def detect_openclaw():
    """
    检测 OpenClaw 运行方式
    返回: (mode, target_dict)
      mode: 'docker' | 'native' | None
    """
    # 1. Docker 容器（所有平台都可能有）
    try:
        r = subprocess.run(
            "docker ps -a --format {{.Names}}",
            shell=True, capture_output=True, timeout=5
        )
        stdout = r.stdout.decode("utf-8", errors="replace").strip() if r.stdout else ""
        for c in stdout.split("\n"):
            c = c.strip()
            if "openclaw" in c.lower():
                rp = subprocess.run(
                    f'docker ps --filter "name=^{c}$" --format {{{{.Names}}}}',
                    shell=True, capture_output=True, timeout=5
                )
                rp_out = rp.stdout.decode("utf-8", errors="replace").strip() if rp.stdout else ""
                running = c in rp_out

                port = 18789
                port_r = subprocess.run(
                    f"docker port {c}", shell=True, capture_output=True, timeout=5
                )
                port_out = port_r.stdout.decode("utf-8", errors="replace").strip() if port_r.stdout else ""
                for line in port_out.split("\n"):
                    if "->" in line:
                        try:
                            port = int(line.split(":")[-1])
                        except:
                            pass
                return "docker", {"name": c, "running": running, "port": port}
    except:
        pass

    # 2. 本地安装
    config_path = find_local_config()
    if config_path:
        cfg = _read_json(config_path)
        port = cfg.get("gateway", {}).get("port", 18789)
        return "native", {"config_path": str(config_path), "port": port}

    return None, {"port": 18789}


def find_local_config():
    """查找本地 OpenClaw 配置文件"""
    home = Path.home()
    candidates = [
        home / ".openclaw" / "openclaw.json",
        home / ".config" / "openclaw" / "openclaw.json",
    ]
    if PLATFORM == "Windows":
        appdata = os.environ.get("LOCALAPPDATA", "")
        if appdata:
            candidates.insert(0, Path(appdata) / "openclaw" / "openclaw.json")
    elif PLATFORM == "Darwin":
        candidates.insert(0, home / "Library" / "Application Support" / "openclaw" / "openclaw.json")

    for p in candidates:
        if p.exists():
            return p
    return None


def find_openclaw_cmd():
    """查找 openclaw 命令路径"""
    # 优先找 openclaw
    oc = shutil.which("openclaw")
    if oc:
        return oc
    # Windows: 尝试常见安装路径
    if PLATFORM == "Windows":
        for p in [
            Path.home() / ".openclaw" / "openclaw.exe",
            Path("C:/Program Files/OpenClaw/openclaw.exe"),
            Path(os.environ.get("APPDATA", "")) / "npm" / "openclaw.cmd",
            Path(os.environ.get("APPDATA", "")) / "npm" / "openclaw.exe",
        ]:
            if p.exists():
                return str(p)
    # macOS: brew 安装路径
    elif PLATFORM == "Darwin":
        for p in [Path("/usr/local/bin/openclaw"), Path("/opt/homebrew/bin/openclaw")]:
            if p.exists():
                return str(p)
    # Linux
    else:
        for p in [Path("/usr/local/bin/openclaw"), Path("/usr/bin/openclaw")]:
            if p.exists():
                return str(p)
    return None


# ============================================================
#  工具函数
# ============================================================

def ensure_dirs():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)


def load_cache():
    if CACHE_FILE.exists():
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except:
            pass
    return {}


def save_cache(data):
    ensure_dirs()
    cache = load_cache()
    cache.update(data)
    with open(CACHE_FILE, "w", encoding="utf-8") as f:
        json.dump(cache, f, indent=2, ensure_ascii=False)


def run_cmd(cmd, timeout=15):
    try:
        # Windows 下隐藏控制台窗口
        startupinfo = None
        if PLATFORM == "Windows":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = subprocess.SW_HIDE
        
        r = subprocess.run(
            cmd, 
            shell=True, 
            capture_output=True, 
            timeout=timeout,
            startupinfo=startupinfo
        )
        stdout = r.stdout.decode("utf-8", errors="replace").strip() if r.stdout else ""
        stderr = r.stderr.decode("utf-8", errors="replace").strip() if r.stderr else ""
        return stdout, stderr, r.returncode
    except subprocess.TimeoutExpired:
        return "", "命令超时", 1
    except Exception as e:
        return "", str(e), 1


def _read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {}


# 全局缓存
_model_caps_cache = None
_model_caps_cache_time = 0


def load_session():
    """加载 New-API Session"""
    return _read_json(SESSION_FILE)


def save_session(data):
    """保存 New-API Session"""
    ensure_dirs()
    with open(SESSION_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def clear_session():
    """清除 Session"""
    if SESSION_FILE.exists():
        SESSION_FILE.unlink()


def format_tokens(tokens):
    """格式化 token 数量"""
    if tokens >= 1048576:
        return f"{tokens / 1048576:.1f}M"
    elif tokens >= 1024:
        return f"{tokens / 1024:.0f}K"
    return str(tokens)


def port_open(port, host="127.0.0.1", timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except:
        return False


def _oc_gateway(action, timeout=30):
    """执行 openclaw gateway 子命令，返回 (stdout, stderr, returncode)"""
    oc = find_openclaw_cmd()
    if not oc:
        return "", "未找到 openclaw 命令", 1
    return run_cmd(f'"{oc}" gateway {action}', timeout=timeout)


# ============================================================
#  配置读写
# ============================================================

def read_config():
    mode, target = detect_openclaw()

    if mode == "docker":
        name = target["name"]
        out, _, rc = run_cmd(f"docker exec {name} cat /home/node/.openclaw/openclaw.json")
        if rc == 0 and out.strip():
            try:
                return json.loads(out)
            except:
                pass
        # docker cp 兜底
        tmp_path = os.path.join(tempfile.gettempdir(), "oc_cfg_tmp.json")
        try:
            run_cmd(f"docker cp {name}:/home/node/.openclaw/openclaw.json {tmp_path}")
            return _read_json(tmp_path)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    elif mode == "native":
        return _read_json(target["config_path"])

    return {}


def write_config(cfg):
    mode, target = detect_openclaw()
    content = json.dumps(cfg, indent=2, ensure_ascii=False)

    if mode == "docker":
        name = target["name"]
        running = target.get("running", False)
        tmp_path = os.path.join(tempfile.gettempdir(), "oc_cfg_tmp.json")
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                f.write(content)
            _, err, rc = run_cmd(f"docker cp {tmp_path} {name}:/home/node/.openclaw/openclaw.json")
            if rc != 0:
                return False
            if running:
                run_cmd(f"docker restart {name}", timeout=30)
            return True
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    elif mode == "native":
        p = Path(target["config_path"])
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                f.write(content)
            return True
        except:
            return False

    return False


# ============================================================
#  API 桥接
# ============================================================

class ApiBridge:

    def __init__(self):
        ensure_dirs()

    # ================================================================
    #  状态
    # ================================================================

    def get_platform_info(self):
        """快速返回平台信息（本地获取，无网络请求）"""
        mode, target = detect_openclaw()
        version_type = self._detect_openclaw_version_type()
        
        # 从配置文件读取端口
        cfg = read_config()
        port = cfg.get('gateway', {}).get('port', 18789)
        
        # 获取版本号
        oc = find_openclaw_cmd()
        version = ""
        if oc:
            out, _, rc = run_cmd(f'"{oc}" --version', timeout=5)
            if rc == 0:
                version = out.strip()
        
        return {
            "platform": PLATFORM,
            "mode": mode or "未检测到",
            "port": port,
            "version_type": version_type,
            "version": version
        }

    def check_api_connectivity(self):
        """单独检测 API 连通性（供前端异步调用）"""
        cache = load_cache()
        api_key = cache.get("api_key", "")
        
        if not api_key:
            return {"ok": False, "msg": "未配置 API Key"}
        
        try:
            r = requests.head(
                f"{AIKUN_BASE}/models",
                headers={"Authorization": f"Bearer {api_key}"},
                timeout=2,
                allow_redirects=True
            )
            ok = r.status_code < 500
            save_cache({"api_connected": ok, "api_last_check": time.time()})
            return {"ok": ok, "msg": "正常" if ok else f"HTTP {r.status_code}"}
        except requests.exceptions.Timeout:
            save_cache({"api_connected": False, "api_last_check": time.time()})
            return {"ok": False, "msg": "超时"}
        except Exception as e:
            save_cache({"api_connected": False, "api_last_check": time.time()})
            return {"ok": False, "msg": str(e)[:50]}

    def get_openclaw_status(self):
        """快速获取 OpenClaw 运行状态（端口检测）"""
        mode, target = detect_openclaw()
        
        if not mode:
            return {"running": False, "status": "未检测到", "mode": None, "port": 18789}
        
        # Docker 模式
        if mode == "docker":
            name = target.get("name", "")
            running = target.get("running", False)
            return {
                "running": running,
                "status": "运行中" if running else "已停止",
                "mode": "docker",
                "name": name,
                "port": target.get("port", 18789)
            }
        
        # Native 模式：从配置文件读取端口，然后检测该端口
        port = target.get("port", 18789)
        
        # 检测函数
        def check_port(p):
            if PLATFORM == "Windows":
                try:
                    import subprocess
                    result = subprocess.run(
                        ['netstat', '-ano'],
                        capture_output=True, timeout=3,
                        creationflags=subprocess.CREATE_NO_WINDOW
                    )
                    output = result.stdout.decode('utf-8', errors='replace')
                    for line in output.split('\n'):
                        if f':{p}' in line and 'LISTENING' in line:
                            return True
                except:
                    pass
            else:
                try:
                    import subprocess
                    result = subprocess.run(
                        ['lsof', '-i', f':{p}'],
                        capture_output=True, timeout=3
                    )
                    if result.returncode == 0 and len(result.stdout) > 0:
                        return True
                except:
                    pass
            return False
        
        # 先检查配置文件中的端口
        running = False
        actual_port = port
        
        if check_port(port):
            running = True
            actual_port = port
        else:
            # 如果配置端口没开，扫描常见端口
            for p in [18789, 18791, 18792, 3000, 8080]:
                if p != port and check_port(p):
                    running = True
                    actual_port = p
                    break
        
        return {
            "running": running,
            "status": "运行中" if running else "已停止",
            "mode": "native",
            "port": actual_port
        }

    def set_custom_port(self, port):
        """设置自定义检测端口"""
        cache = load_cache()
        cache["custom_port"] = port
        save_cache(cache)
        return {"ok": True, "msg": f"已设置自定义端口: {port}"}

    def set_scan_ports(self, ports):
        """设置扫描端口列表"""
        cache = load_cache()
        cache["scan_ports"] = ports
        save_cache(cache)
        return {"ok": True, "msg": f"已设置扫描端口: {ports}"}

    def get_status(self):
        cache = load_cache()
        api_key = cache.get("api_key", "")
        mode, target = detect_openclaw()

        # 运行状态 + 服务信息
        running = False
        container_name = ""
        service_status = "未知"

        if mode == "docker":
            running = target.get("running", False)
            container_name = target.get("name", "")
            service_status = "运行中" if running else "已停止"

        elif mode == "native":
            # 用官方命令检测
            out, err, rc = _oc_gateway("status", timeout=5)  # 减少超时
            combined = out + "\n" + err

            # 解析状态
            if "Runtime: running" in combined or "Capability: ready" in combined:
                running = True
                service_status = "运行中"
            elif "Runtime: stopped" in combined:
                running = False
                service_status = "已停止"
            elif "Service not installed" in combined or "missing" in combined.lower():
                running = False
                service_status = "服务未安装"
            else:
                # 兜底：端口检测
                running = port_open(target.get("port", 18789))
                service_status = "运行中" if running else "已停止"

        # 端口
        port = target.get("port", 18789)

        # 配置（使用缓存的配置）
        cfg = read_config() if (running or mode == "native") else {}
        models = cfg.get("models", {}).get("providers", {}).get("aikun", {}).get("models", [])
        primary = cfg.get("agents", {}).get("defaults", {}).get("model", {}).get("primary", "")

        # API 连通（使用缓存，极简检测）
        api_ok = cache.get("api_connected", None)  # None 表示未检测
        api_last_check = cache.get("api_last_check", 0)
        current_time = time.time()
        
        # 每 120 秒检测一次，用 HEAD 请求
        if current_time - api_last_check > 120:
            if api_key:
                try:
                    # 极简检测：HEAD 请求，2秒超时
                    r = requests.head(
                        f"{AIKUN_BASE}/models",
                        headers={"Authorization": f"Bearer {api_key}"},
                        timeout=2,
                        allow_redirects=True
                    )
                    api_ok = r.status_code < 500  # 只要不是服务器错误就算通
                    save_cache({"api_connected": api_ok, "api_last_check": current_time})
                except requests.exceptions.Timeout:
                    api_ok = False
                    save_cache({"api_connected": False, "api_last_check": current_time})
                except:
                    api_ok = False
                    save_cache({"api_connected": False, "api_last_check": current_time})
            else:
                api_ok = False

        # 网关连通（使用缓存）
        gw_ok = cache.get("gateway_accessible", False)
        gw_last_check = cache.get("gateway_last_check", 0)
        
        # 每 60 秒检测一次
        if current_time - gw_last_check > 60:
            gw_ok = port_open(port)
            save_cache({"gateway_accessible": gw_ok, "gateway_last_check": current_time})

        return {
            "platform": PLATFORM,
            "mode": mode or "未检测到",
            "service_status": service_status,
            "api_key_set": bool(api_key),
            "api_key_masked": f"{api_key[:8]}****" if api_key else "",
            "api_connected": api_ok,
            "container_name": container_name,
            "container_running": running,
            "gateway_accessible": gw_ok,
            "gateway_port": port,
            "model_count": len(models),
            "models": [m.get("id", "") for m in models],
            "default_model": primary.replace("aikun/", "") if primary else "",
            "base_url": AIKUN_BASE,
            "ai_site": AIKUN_SITE,
        }

    def get_api_key(self):
        """获取保存的 API Key"""
        cache = load_cache()
        return cache.get("api_key", "")

    def get_balance(self):
        """获取 AI坤 积分余额（通过 Session 获取真实余额）"""
        session_data = load_session()
        if not session_data.get("logged_in"):
            return {"ok": False, "balance": 0, "total": 0, "used": 0, "msg": "未登录", "need_login": True}

        try:
            # 使用 Session 的 cookies
            cookies = session_data.get("cookies", {})
            user_id = session_data.get("user_id", 1)
            
            # 获取用户信息（包含余额），需要带 New-Api-User header
            headers = {"New-Api-User": str(user_id)}
            r = requests.get(
                f"{AIKUN_SITE}/api/user/self",
                cookies=cookies,
                headers=headers,
                timeout=10
            )
            if r.status_code != 200:
                clear_session()
                return {"ok": False, "balance": 0, "total": 0, "used": 0, "msg": "Session 已过期，请重新登录", "need_login": True}

            data = r.json()
            if not data.get("success"):
                clear_session()
                return {"ok": False, "balance": 0, "total": 0, "used": 0, "msg": "Session 无效，请重新登录", "need_login": True}

            user = data.get("data", {})
            quota = user.get("quota", 0)
            used_quota = user.get("used_quota", 0)
            
            # quota_per_unit = 500000，转换为积分
            quota_per_unit = 500000
            balance = quota / quota_per_unit
            used = used_quota / quota_per_unit
            total = balance + used

            return {
                "ok": True,
                "total": round(total, 2),
                "used": round(used, 4),
                "balance": round(balance, 2),
                "is_unlimited": False,
                "msg": f"{balance:.2f} 积分",
                "username": user.get("username", ""),
                "logged_in": True
            }
        except Exception as e:
            return {"ok": False, "balance": 0, "total": 0, "used": 0, "msg": str(e)}

    # ================================================================
    #  New-API 登录

    def update_gateway_token(self, new_token):
        """更新网关令牌"""
        if not new_token or not new_token.strip():
            return {"ok": False, "msg": "令牌不能为空"}
        cfg = read_config()
        cfg.setdefault("gateway", {}).setdefault("auth", {})  ["token"] = new_token.strip()
        if write_config(cfg):
            return {"ok": True, "msg": "网关令牌已更新"}
        return {"ok": False, "msg": "写入配置失败"}

    # ================================================================
    #  New-API 登录
    # ================================================================

    def login_aikun(self, username, password):
        """登录 New-API 获取 Session"""
        if not username or not password:
            return {"ok": False, "msg": "用户名和密码不能为空"}

        try:
            # 创建 session 对象
            session = requests.Session()
            
            # 登录
            login_data = {
                "username": username,
                "password": password
            }
            r = session.post(
                f"{AIKUN_SITE}/api/user/login",
                json=login_data,
                timeout=10
            )
            
            if r.status_code != 200:
                return {"ok": False, "msg": f"登录失败: HTTP {r.status_code}"}

            data = r.json()
            if not data.get("success"):
                return {"ok": False, "msg": data.get("message", "用户名或密码错误")}

            # 登录成功，保存 cookies
            user_data = data.get("data", {})
            cookies = dict(session.cookies)
            
            save_session({
                "logged_in": True,
                "username": user_data.get("username", username),
                "user_id": user_data.get("id", 1),
                "cookies": cookies,
                "login_time": time.time()
            })

            return {
                "ok": True,
                "msg": f"登录成功，欢迎 {user_data.get('username', username)}",
                "username": user_data.get("username", username)
            }
        except Exception as e:
            return {"ok": False, "msg": f"登录失败: {str(e)}"}

    def logout_aikun(self):
        """退出 New-API 登录"""
        session_data = load_session()
        if session_data.get("logged_in"):
            try:
                cookies = session_data.get("cookies", {})
                requests.get(
                    f"{AIKUN_SITE}/api/user/logout",
                    cookies=cookies,
                    timeout=5
                )
            except:
                pass
        clear_session()
        return {"ok": True, "msg": "已退出登录"}

    def get_login_status(self):
        """获取登录状态"""
        session_data = load_session()
        if session_data.get("logged_in"):
            return {
                "logged_in": True,
                "username": session_data.get("username", ""),
                "login_time": session_data.get("login_time", 0)
            }
        return {"logged_in": False}

    def get_usage_info(self):
        """返回使用信息，供前端跳转"""
        cfg = read_config()
        port = cfg.get('gateway', {}).get('port', 18789)
        token = cfg.get('gateway', {}).get('auth', {}).get('token', '') or cfg.get('gateway', {}).get('token', '')

        return {
            'api_url': AIKUN_BASE,
            'web_url': f'http://127.0.0.1:{port}',
            'token': token,
            'site': AIKUN_SITE,
        }

    # ================================================================
    #  API Key
    # ================================================================

    def set_api_key(self, key):
        if not key or not key.strip():
            return {"ok": False, "msg": "API Key 不能为空"}
        key = key.strip()
        try:
            r = requests.get(f"{AIKUN_BASE}/models", headers={"Authorization": f"Bearer {key}"}, timeout=10)
            if r.status_code != 200:
                return {"ok": False, "msg": f"API 返回 {r.status_code}，Key 可能无效"}
        except Exception as e:
            return {"ok": False, "msg": f"连接失败: {e}"}
        save_cache({"api_key": key})
        return {"ok": True, "msg": "API Key 已保存，连通性正常"}

    # ================================================================
    #  模型
    # ================================================================

    def fetch_models(self):
        cache = load_cache()
        api_key = cache.get("api_key", "")
        if not api_key:
            return {"ok": False, "msg": "请先配置 API Key", "models": []}
        try:
            r = requests.get(f"{AIKUN_BASE}/models", headers={"Authorization": f"Bearer {api_key}"}, timeout=15)
            if r.status_code != 200:
                return {"ok": False, "msg": f"API 返回 {r.status_code}", "models": []}
            return {"ok": True, "models": [{"id": m["id"], "owned_by": m.get("owned_by", "")} for m in r.json().get("data", [])]}
        except Exception as e:
            return {"ok": False, "msg": str(e), "models": []}

    def get_enabled_models(self):
        cfg = read_config()
        models = cfg.get("models", {}).get("providers", {}).get("aikun", {}).get("models", [])
        primary = cfg.get("agents", {}).get("defaults", {}).get("model", {}).get("primary", "")
        return {
            "models": [{"id": m.get("id", ""), "name": m.get("name", m.get("id", ""))} for m in models],
            "default": primary.replace("aikun/", "") if primary else "",
        }

    def save_models(self, model_ids, default_model):
        if not model_ids:
            return {"ok": False, "msg": "至少选择一个模型"}
        cache = load_cache()
        api_key = cache.get("api_key", "")
        cfg = read_config()
        
        # 构建模型列表（基本功能，不含能力配置）
        models_list = [{"id": mid, "name": mid} for mid in model_ids]
        
        # models.providers: 只操作 aikun
        cfg.setdefault("models", {})["mode"] = "merge"
        cfg["models"].setdefault("providers", {})["aikun"] = {
            "baseUrl": AIKUN_BASE,
            "apiKey": api_key,
            "api": "openai-completions",
            "models": models_list,
        }

        # agents.defaults.models: 合并模式
        defaults = cfg.setdefault("agents", {}).setdefault("defaults", {})
        existing_models = defaults.get("models", {})
        cleaned = {k: v for k, v in existing_models.items() if not k.startswith("aikun/")}
        for mid in model_ids:
            cleaned[f"aikun/{mid}"] = {}
        defaults["models"] = cleaned

        # primary: 仅当当前是 aikun 或未设置时才更新
        current_primary = defaults.get("model", {}).get("primary", "")
        if not current_primary or current_primary.startswith("aikun/"):
            defaults.setdefault("model", {})["primary"] = f"aikun/{default_model}"

        if write_config(cfg):
            return {"ok": True, "msg": f"已保存 {len(model_ids)} 个模型，默认: {default_model}"}
        return {"ok": False, "msg": "写入配置失败"}

    def set_default_model(self, model_id):
        """设置默认模型"""
        cfg = read_config()
        defaults = cfg.setdefault("agents", {}).setdefault("defaults", {})
        defaults.setdefault("model", {})["primary"] = f"aikun/{model_id}"
        
        if write_config(cfg):
            return {"ok": True, "msg": f"已将 {model_id} 设为默认模型"}
        return {"ok": False, "msg": "写入配置失败"}

    # ================================================================
    #  服务管理 — 对齐官方 CLI
    # ================================================================

    def service_action(self, action):
        """
        启停重启，使用官方命令:
          openclaw gateway install / start / stop / restart / status / uninstall
        Docker 模式使用 docker 命令
        根据安装版本（原版/中文版）适配命令
        """
        mode, target = detect_openclaw()
        version_type = self._detect_openclaw_version_type()

        if not mode:
            return {"ok": False, "msg": "未检测到 OpenClaw 安装"}

        # ---- Docker 模式 ----
        if mode == "docker":
            name = target["name"]
            cmds = {
                "start":   f"docker start {name}",
                "stop":    f"docker stop {name}",
                "restart": f"docker restart {name}",
            }
            cmd = cmds.get(action)
            if not cmd:
                return {"ok": False, "msg": f"未知操作: {action}"}
            out, err, rc = run_cmd(cmd, timeout=20)
            if rc == 0:
                save_cache({"api_last_check": 0, "gateway_last_check": 0})
                return {"ok": True, "msg": f"OpenClaw 已{action}"}
            return {"ok": False, "msg": f"失败: {err}"}

        # ---- Native 模式 ----
        oc = find_openclaw_cmd()
        if not oc:
            if version_type == "chinese":
                return {"ok": False, "msg": "未找到 openclaw 命令，请运行: npm install -g @qingchencloud/openclaw-zh@latest"}
            return {"ok": False, "msg": "未找到 openclaw 命令，请运行: npm install -g openclaw@latest"}

        # start / restart 前确保服务已安装
        if action in ("start", "restart"):
            out, _, rc = _oc_gateway("status", timeout=5)
            if "Service not installed" in out or "missing" in out.lower():
                ins_out, ins_err, ins_rc = _oc_gateway("install", timeout=20)
                if ins_rc != 0:
                    return {"ok": False, "msg": f"服务安装失败: {ins_err[:200]}"}

        # 执行官方命令
        cmd_map = {
            "start":    ("start", 15),
            "stop":     ("stop",  10),
            "restart":  ("restart", 20),
            "install":  ("install", 20),
            "uninstall": ("uninstall", 10),
        }
        if action in cmd_map:
            sub, timeout = cmd_map[action]
            out, err, rc = _oc_gateway(sub, timeout=timeout)

            if rc == 0:
                save_cache({"api_last_check": 0, "gateway_last_check": 0})
                if action in ("start", "restart"):
                    ok = port_open(target.get("port", 18789))
                    if ok:
                        return {"ok": True, "msg": f"OpenClaw 已{action}"}
                    return {"ok": False, "msg": f"命令执行完成但端口未监听，可能启动中"}
                return {"ok": True, "msg": f"OpenClaw 已{action}"}

            # 解析错误
            combined = (out + " " + err).lower()
            if "socks.connect" in combined or "socks" in combined:
                return {"ok": False, "msg": "SOCKS 代理连接失败，请关闭代理软件或检查代理设置"}
            if "eaddrinuse" in combined or "address already in use" in combined:
                return {"ok": False, "msg": "端口已被占用，请检查是否有其他实例在运行"}
            if "schtasks" in combined:
                return {"ok": False, "msg": f"Windows 计划任务错误: {err[:200]}"}
            return {"ok": False, "msg": f"命令失败: {(err or out)[:200]}"}

        return {"ok": False, "msg": f"未知操作: {action}"}

    # ================================================================
    #  日志
    # ================================================================

    def get_logs(self, lines=50):
        mode, target = detect_openclaw()
        if mode == "docker":
            name = target["name"]
            out, _, rc = run_cmd(f"docker logs --tail {lines} {name}", timeout=10)
            if rc == 0:
                return {"ok": True, "logs": out}

        elif mode == "native":
            # Windows 日志路径
            if PLATFORM == "Windows":
                log_dir = Path(os.environ.get("TEMP", "")) / "openclaw"
            elif PLATFORM == "Darwin":
                log_dir = Path.home() / "Library" / "Logs" / "openclaw"
            else:
                log_dir = Path("/tmp/openclaw")

            if log_dir.exists():
                log_files = sorted(log_dir.glob("openclaw-*.log"), reverse=True)
                if log_files:
                    try:
                        with open(log_files[0], "r", encoding="utf-8", errors="replace") as f:
                            all_lines = f.readlines()
                        return {"ok": True, "logs": "".join(all_lines[-lines:])}
                    except:
                        pass

        return {"ok": False, "logs": "无法读取日志"}

    # ================================================================
    #  配置备份 / 恢复
    # ================================================================

    def backup_config(self):
        cfg = read_config()
        if not cfg:
            return {"ok": False, "msg": "无法读取配置"}
        ts = time.strftime("%Y%m%d_%H%M%S")
        backup_path = BACKUP_DIR / f"openclaw_{ts}.json"
        ensure_dirs()
        with open(backup_path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
        return {"ok": True, "msg": f"备份成功: {backup_path.name}", "path": str(backup_path)}

    def restore_config(self, filename=None):
        if not filename:
            backups = sorted(BACKUP_DIR.glob("openclaw_*.json"), reverse=True)
            if not backups:
                return {"ok": False, "msg": "没有备份文件"}
            filename = backups[0].name
        backup_path = BACKUP_DIR / filename
        if not backup_path.exists():
            return {"ok": False, "msg": f"备份文件不存在: {filename}"}
        cfg = _read_json(backup_path)
        if not cfg:
            return {"ok": False, "msg": "备份文件为空或格式错误"}
        if write_config(cfg):
            return {"ok": True, "msg": f"已恢复: {filename}"}
        return {"ok": False, "msg": "写入配置失败"}

    def list_backups(self):
        ensure_dirs()
        backups = sorted(BACKUP_DIR.glob("openclaw_*.json"), reverse=True)
        return [{"name": b.name, "size": b.stat().st_size, "time": b.stat().st_mtime} for b in backups]

    # ================================================================
    #  环境诊断
    # ================================================================

    def run_diagnostics(self):
        """运行诊断，适配不同系统"""
        cache = load_cache()
        mode, target = detect_openclaw()
        results = []

        # ---- 基础依赖 ----
        # Node.js（native 模式需要）
        if mode == "native" or not mode:
            node_ok = shutil.which("node") is not None
            node_ver = ""
            if node_ok:
                out, _, _ = run_cmd("node --version", timeout=3)
                node_ver = out.strip()
            results.append({
                "name": "Node.js",
                "ok": node_ok,
                "fixable": False,
                "msg": node_ver if node_ok else "未安装",
                "fix_hint": "请从 nodejs.org 下载安装" if not node_ok else "",
            })

        # openclaw 命令（native 模式需要）
        if mode == "native" or not mode:
            oc = find_openclaw_cmd()
            oc_ver = ""
            if oc:
                out, _, rc = run_cmd(f'"{oc}" --version', timeout=5)
                oc_ver = out.strip() if rc == 0 else ""
            
            # 检测版本类型
            version_type = self._detect_openclaw_version_type()
            if version_type == "chinese":
                install_hint = "npm install -g @qingchencloud/openclaw-zh@latest"
            else:
                install_hint = "npm install -g openclaw@latest"
            
            results.append({
                "name": "OpenClaw CLI",
                "ok": bool(oc),
                "fixable": False,
                "msg": oc_ver if oc else "未安装",
                "fix_hint": install_hint if not oc else "",
            })

        # Docker（仅检测，不强制）
        docker_ok = shutil.which("docker") is not None
        if docker_ok:
            _, _, rc = run_cmd("docker info", timeout=5)
            docker_daemon = rc == 0
            results.append({
                "name": "Docker",
                "ok": docker_daemon,
                "fixable": False,
                "msg": "已安装，服务运行中" if docker_daemon else "已安装但服务未启动",
                "fix_hint": "" if docker_daemon else "请启动 Docker Desktop",
            })
        else:
            results.append({
                "name": "Docker",
                "ok": False,
                "fixable": False,
                "msg": "未安装（可选）",
                "fix_hint": "群晖/飞牛在套件中心安装；Windows/macOS 去 docker.com 下载",
            })

        # ---- OpenClaw 服务 ----
        if mode == "docker":
            running = target.get("running", False)
            results.append({
                "name": "OpenClaw (Docker)",
                "ok": running,
                "fixable": True,
                "msg": f"运行中 ({target['name']})" if running else f"已停止 ({target['name']})",
                "fix_hint": "启动容器" if not running else "",
                "fix_action": "start_container" if not running else "",
            })
        elif mode == "native":
            # 用官方 status 命令检测
            out, err, rc = _oc_gateway("status", timeout=10)
            combined = out + "\n" + err

            running = "Runtime: running" in combined
            service_installed = "Service not installed" not in combined and "missing" not in combined.lower()

            if not service_installed:
                results.append({
                    "name": "OpenClaw 服务",
                    "ok": False,
                    "fixable": True,
                    "msg": "服务未安装",
                    "fix_hint": "需要安装服务才能后台运行",
                    "fix_action": "install_service",
                })
            else:
                results.append({
                    "name": "OpenClaw 服务",
                    "ok": running,
                    "fixable": True,
                    "msg": "运行中" if running else "已停止",
                    "fix_hint": "启动服务" if not running else "",
                    "fix_action": "start_service" if not running else "",
                })
        else:
            results.append({
                "name": "OpenClaw",
                "ok": False,
                "fixable": False,
                "msg": "未检测到",
                "fix_hint": "请使用下方一键安装",
            })

        # ---- 网关端口 ----
        port = target.get("port", 18789)
        gw_ok = port_open(port)
        results.append({
            "name": f"网关端口 ({port})",
            "ok": gw_ok,
            "fixable": False,
            "msg": "可达" if gw_ok else "不可达",
            "fix_hint": "请检查 OpenClaw 是否运行" if not gw_ok else "",
        })

        # ---- 代理检测 ----
        proxy_vars = []
        for var in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "SOCKS_PROXY"]:
            val = os.environ.get(var, "").strip()
            if val:
                proxy_vars.append(f"{var}={val}")

        if proxy_vars:
            results.append({
                "name": "代理环境变量",
                "ok": False,
                "fixable": False,
                "msg": f"检测到: {', '.join(proxy_vars[:2])}",
                "fix_hint": "如果代理未运行可能导致连接失败",
            })

        # ---- AI坤 API ----
        api_key = cache.get("api_key", "")
        if api_key:
            try:
                r = requests.get(f"{AIKUN_BASE}/models", headers={"Authorization": f"Bearer {api_key}"}, timeout=8)
                api_ok = r.status_code == 200
            except:
                api_ok = False
            results.append({
                "name": "AI坤 API",
                "ok": api_ok,
                "fixable": False,
                "msg": "连通正常" if api_ok else "连接失败",
                "fix_hint": "请检查网络或 API Key" if not api_ok else "",
            })
        else:
            results.append({
                "name": "AI坤 API Key",
                "ok": False,
                "fixable": False,
                "msg": "未配置",
                "fix_hint": "请在模型管理中配置",
            })

        # ---- 配置文件 ----
        cfg = read_config()
        has_aikun = bool(cfg.get("models", {}).get("providers", {}).get("aikun", {}).get("apiKey"))
        results.append({
            "name": "供应商配置",
            "ok": has_aikun,
            "fixable": False,
            "msg": "已配置 AI坤" if has_aikun else "未配置",
            "fix_hint": "请在模型管理中配置" if not has_aikun else "",
        })
        
        # 检查配置文件有效性
        oc = find_openclaw_cmd()
        if oc:
            out, _, rc = run_cmd(f'"{oc}" config validate', timeout=10)
            config_valid = rc == 0 and "invalid" not in out.lower()
            if not config_valid:
                results.append({
                    "name": "配置文件有效性",
                    "ok": False,
                    "fixable": True,
                    "msg": "配置无效",
                    "fix_hint": "运行 openclaw doctor --fix 修复",
                    "fix_action": "fix_config",
                })
        
        # 检查模型字段名是否正确
        models = cfg.get("models", {}).get("providers", {}).get("aikun", {}).get("models", [])
        if models:
            has_wrong_fields = False
            for m in models:
                if "context_length" in m or "max_output_tokens" in m:
                    has_wrong_fields = True
                    break
            if has_wrong_fields:
                results.append({
                    "name": "模型字段名",
                    "ok": False,
                    "fixable": True,
                    "msg": "使用了旧字段名",
                    "fix_hint": "context_length 应为 contextWindow，max_output_tokens 应为 maxTokens",
                    "fix_action": "fix_model_fields",
                })

        return results

    def fix_issue(self, action):
        """执行一键修复"""
        if action == "start_container":
            mode, target = detect_openclaw()
            if mode == "docker":
                _, err, rc = run_cmd(f"docker start {target['name']}", timeout=30)
                if rc == 0:
                    time.sleep(3)
                    return {"ok": True, "msg": "容器已启动"}
                return {"ok": False, "msg": f"启动失败: {err}"}
            return {"ok": False, "msg": "非 Docker 模式"}

        elif action == "install_service":
            out, err, rc = _oc_gateway("install", timeout=30)
            if rc == 0:
                return {"ok": True, "msg": "服务已安装"}
            return {"ok": False, "msg": f"安装失败: {err[:200]}"}

        elif action == "start_service":
            out, err, rc = _oc_gateway("start", timeout=30)
            time.sleep(2)
            if rc == 0 or port_open(18789):
                return {"ok": True, "msg": "服务已启动"}
            return {"ok": False, "msg": f"启动失败: {(err or out)[:200]}"}

        elif action == "fix_config":
            oc = find_openclaw_cmd()
            if not oc:
                return {"ok": False, "msg": "未找到 openclaw 命令"}
            out, err, rc = run_cmd(f'"{oc}" doctor --fix', timeout=30)
            if rc == 0:
                return {"ok": True, "msg": "配置已修复"}
            return {"ok": False, "msg": f"修复失败: {err[:200]}"}

        elif action == "fix_model_fields":
            cfg = read_config()
            models = cfg.get("models", {}).get("providers", {}).get("aikun", {}).get("models", [])
            fixed = 0
            for m in models:
                if "context_length" in m:
                    m["contextWindow"] = m.pop("context_length")
                    fixed += 1
                if "max_output_tokens" in m:
                    m["maxTokens"] = m.pop("max_output_tokens")
                    fixed += 1
            if fixed > 0 and write_config(cfg):
                return {"ok": True, "msg": f"已修复 {fixed} 个字段名"}
            return {"ok": False, "msg": "未发现需要修复的字段"}

        return {"ok": False, "msg": "未知修复操作"}

    # ================================================================
    #  自身诊断
    # ================================================================

    def scan_self_garbage(self):
        """扫描管理工具自身的垃圾文件"""
        garbage = []
        total_size = 0

        # 1. 临时文件
        temp_patterns = ["*.tmp", "*.temp", "*.log", "*.bak"]
        for pattern in temp_patterns:
            for f in CACHE_DIR.glob(pattern):
                size = f.stat().st_size
                total_size += size
                garbage.append({
                    "path": str(f),
                    "name": f.name,
                    "size": size,
                    "type": "临时文件",
                    "modified": f.stat().st_mtime
                })

        # 2. 旧备份（保留最近5个）
        backups = sorted(BACKUP_DIR.glob("openclaw_*.json"), reverse=True)
        if len(backups) > 5:
            for old_backup in backups[5:]:
                size = old_backup.stat().st_size
                total_size += size
                garbage.append({
                    "path": str(old_backup),
                    "name": old_backup.name,
                    "size": size,
                    "type": "旧备份",
                    "modified": old_backup.stat().st_mtime
                })

        # 3. Session 文件（如果未登录）
        session_data = load_session()
        if not session_data.get("logged_in") and SESSION_FILE.exists():
            size = SESSION_FILE.stat().st_size
            total_size += size
            garbage.append({
                "path": str(SESSION_FILE),
                "name": SESSION_FILE.name,
                "size": size,
                "type": "过期Session",
                "modified": SESSION_FILE.stat().st_mtime
            })

        # 4. 缓存目录大小
        cache_size = sum(f.stat().st_size for f in CACHE_DIR.rglob("*") if f.is_file())

        return {
            "ok": True,
            "garbage": garbage,
            "total_size": total_size,
            "cache_size": cache_size,
            "cache_dir": str(CACHE_DIR)
        }

    def clean_self_garbage(self, items=None):
        """清理自身垃圾文件"""
        cleaned = 0
        freed = 0

        if items is None:
            # 清理所有垃圾
            result = self.scan_self_garbage()
            items = result.get("garbage", [])

        for item in items:
            try:
                path = Path(item["path"])
                if path.exists():
                    size = path.stat().st_size
                    path.unlink()
                    cleaned += 1
                    freed += size
            except Exception as e:
                print(f"清理失败: {item['name']} - {e}")

        return {
            "ok": True,
            "cleaned": cleaned,
            "freed": freed,
            "msg": f"已清理 {cleaned} 个文件，释放 {freed / 1024:.1f} KB"
        }

    # ================================================================
    #  系统信息（给前端安装选项用）
    # ================================================================

    def get_system_info(self):
        """返回当前系统信息，用于前端展示可用的安装方式"""
        mode, target = detect_openclaw()
        oc = find_openclaw_cmd()
        docker_ok = shutil.which("docker") is not None
        docker_daemon = False
        if docker_ok:
            _, _, rc = run_cmd("docker info", timeout=5)
            docker_daemon = rc == 0

        installed = mode is not None
        install_methods = []

        if not installed:
            # 有 Docker → 推荐容器
            if docker_daemon:
                install_methods.append({"id": "docker", "name": "Docker 容器", "desc": "推荐，一键部署，环境隔离"})
            # Windows
            if PLATFORM == "Windows":
                if not docker_daemon:
                    install_methods.append({"id": "win_native", "name": "Windows 安装包", "desc": "下载 exe 安装包"})
            # macOS
            elif PLATFORM == "Darwin":
                if shutil.which("brew"):
                    install_methods.append({"id": "mac_brew", "name": "Homebrew", "desc": "brew install openclaw"})
                install_methods.append({"id": "mac_native", "name": "macOS 安装包", "desc": "下载 dmg 安装"})
            # Linux
            else:
                if not docker_daemon:
                    install_methods.append({"id": "linux_script", "name": "安装脚本", "desc": "curl 一键安装"})

        return {
            "platform": PLATFORM,
            "installed": installed,
            "mode": mode,
            "oc_cmd": oc is not None,
            "docker": docker_daemon,
            "install_methods": install_methods,
        }

    # ================================================================
    #  外部链接
    # ================================================================

    def open_url(self, url):
        try:
            webbrowser.open(url)
            return {"ok": True}
        except:
            return {"ok": False}

    def open_dashboard(self):
        """打开 OpenClaw Dashboard - 直接打开浏览器访问网关"""
        # 从配置文件读取端口
        cfg = read_config()
        port = cfg.get('gateway', {}).get('port', 18789)
        url = f'http://127.0.0.1:{port}'
        
        # 直接打开浏览器
        try:
            webbrowser.open(url)
            return {"ok": True, "msg": f"已打开 {url}"}
        except Exception as e:
            return {"ok": False, "msg": f"无法打开浏览器: {str(e)}"}

    # ================================================================
    #  一键安装 / 卸载
    # ================================================================

    def install_openclaw(self, method="docker"):
        if method == "docker":
            return self._install_docker()
        elif method == "win_native":
            return self._install_windows()
        elif method == "mac_brew":
            return self._install_macos_brew()
        elif method == "mac_native":
            return self._install_macos_native()
        elif method == "linux_script":
            return self._install_linux_script()
        return {"ok": False, "msg": "不支持的安装方式"}

    def _install_docker(self):
        _, _, rc = run_cmd("docker --version", timeout=5)
        if rc != 0:
            return {"ok": False, "msg": "Docker 未安装"}
        _, _, rc = run_cmd("docker info", timeout=5)
        if rc != 0:
            return {"ok": False, "msg": "Docker 服务未启动"}

        _, err, rc = run_cmd("docker pull openclaw/openclaw:latest", timeout=180)
        if rc != 0:
            return {"ok": False, "msg": f"拉取镜像失败: {err}"}

        token = secrets.token_urlsafe(24)
        run_cmd("docker rm -f openclaw", timeout=10)

        cmd = (
            f'docker run -d --name openclaw --restart unless-stopped '
            f'-p 18789:18789 -e OPENCLAW_GATEWAY_TOKEN={token} '
            f'openclaw/openclaw:latest --allow-unconfigured --port 18789'
        )
        _, err, rc = run_cmd(cmd, timeout=30)
        if rc != 0:
            return {"ok": False, "msg": f"创建容器失败: {err}"}

        time.sleep(5)
        return {"ok": True, "msg": "Docker 安装完成", "token": token, "port": 18789}

    def _install_windows(self):
        webbrowser.open("https://openclaw.com/download")
        return {"ok": True, "msg": "已打开下载页面，请下载安装后重新检测"}

    def _install_macos_brew(self):
        if not shutil.which("brew"):
            return {"ok": False, "msg": "未安装 Homebrew，请先安装"}
        _, err, rc = run_cmd("brew install openclaw", timeout=120)
        if rc == 0:
            return {"ok": True, "msg": "Homebrew 安装完成"}
        return {"ok": False, "msg": f"安装失败: {err}"}

    def _install_macos_native(self):
        webbrowser.open("https://openclaw.com/download")
        return {"ok": True, "msg": "已打开下载页面，请下载 dmg 安装"}

    def _install_linux_script(self):
        cmd = 'curl -fsSL https://openclaw.com/install.sh | sudo bash'
        _, err, rc = run_cmd(cmd, timeout=120)
        if rc == 0:
            return {"ok": True, "msg": "安装完成"}
        return {"ok": False, "msg": f"安装失败: {err}"}

    def install_openclaw_choice(self, version_type="original", options=None):
        """一键安装 OpenClaw（原版或中文版）"""
        if options is None:
            options = {}
        
        if version_type == "chinese":
            return self._install_chinese(options)
        else:
            return self._install_original(options)

    def _install_chinese(self, options=None):
        """安装中文汉化版"""
        if options is None:
            options = {}
        
        # 检查 Node.js
        node_ver, _, node_rc = run_cmd("node --version", timeout=5)
        if node_rc != 0:
            return {"ok": False, "msg": "需要 Node.js 14+，请先安装 Node.js", "need_node": True}
        
        npm_ver, _, npm_rc = run_cmd("npm --version", timeout=5)
        if npm_rc != 0:
            return {"ok": False, "msg": "需要 npm 包管理器"}
        
        # 步骤 1: 安装 npm 包
        # 卸载旧版
        run_cmd("npm uninstall -g @qingchencloud/openclaw-zh", timeout=30)
        run_cmd("npm uninstall -g openclaw", timeout=30)
        
        out, err, rc = run_cmd('npm install -g @qingchencloud/openclaw-zh@latest', timeout=180)
        if rc != 0:
            return {"ok": False, "msg": f"npm 安装失败: {err[:200]}"}
        
        # 验证安装
        ver_out, _, ver_rc = run_cmd('openclaw --version', timeout=10)
        if ver_rc != 0:
            return {"ok": False, "msg": "安装验证失败，请检查 npm 全局路径"}
        
        installed_version = ver_out.strip() if ver_out.strip() else "@qingchencloud/openclaw-zh"
        
        # 步骤 2: 初始化配置
        init_result = self._run_onboard(options)
        
        return {
            "ok": True,
            "msg": "中文汉化版安装完成" + ("，已初始化配置" if init_result else ""),
            "version": installed_version
        }

    def _install_original(self, options=None):
        """安装原版 OpenClaw"""
        if options is None:
            options = {}
        
        # 检查 Node.js
        node_ver, _, node_rc = run_cmd("node --version", timeout=5)
        if node_rc != 0:
            return {"ok": False, "msg": "需要 Node.js 14+，请先安装 Node.js", "need_node": True}
        
        npm_ver, _, npm_rc = run_cmd("npm --version", timeout=5)
        if npm_rc != 0:
            return {"ok": False, "msg": "需要 npm 包管理器"}
        
        # 步骤 1: 安装 npm 包
        # 卸载旧版
        run_cmd("npm uninstall -g @qingchencloud/openclaw-zh", timeout=30)
        run_cmd("npm uninstall -g openclaw", timeout=30)
        
        out, err, rc = run_cmd('npm install -g openclaw@latest', timeout=180)
        if rc != 0:
            return {"ok": False, "msg": f"npm 安装失败: {err[:200]}"}
        
        # 验证安装
        ver_out, _, ver_rc = run_cmd('openclaw --version', timeout=10)
        if ver_rc != 0:
            return {"ok": False, "msg": "安装验证失败，请检查 npm 全局路径"}
        
        installed_version = ver_out.strip() if ver_out.strip() else "openclaw"
        
        # 步骤 2: 初始化配置
        init_result = self._run_onboard(options)
        
        return {
            "ok": True,
            "msg": "原版安装完成" + ("，已初始化配置" if init_result else ""),
            "version": installed_version
        }

    def _run_onboard(self, options=None):
        """运行 openclaw onboard 初始化"""
        if options is None:
            options = {}
        
        # 构建 onboard 命令
        cmd = "openclaw onboard"
        
        # 如果选择安装守护进程
        if options.get("install_daemon", False):
            cmd += " --install-daemon"
        
        # 运行 onboard（非交互模式，使用默认配置）
        # 注意：onboard 是交互式的，这里我们只创建默认配置
        try:
            # 创建默认配置目录
            home = Path.home()
            cfg_dir = home / ".openclaw"
            cfg_dir.mkdir(parents=True, exist_ok=True)
            cfg_path = cfg_dir / "openclaw.json"
            
            if not cfg_path.exists():
                # 生成默认 token
                token = secrets.token_urlsafe(24)
                port = options.get("port", 18789)
                
                default_cfg = {
                    "gateway": {
                        "port": port,
                        "token": token
                    },
                    "meta": {
                        "lastTouchedVersion": ""
                    }
                }
                with open(cfg_path, "w", encoding="utf-8") as f:
                    json.dump(default_cfg, f, indent=2, ensure_ascii=False)
            
            return True
        except Exception as e:
            print(f"初始化配置失败: {e}")
            return False
            if r.status_code == 200:
                latest_ver = r.json().get("version", "latest")
        except:
            pass
        
        # 卸载旧版
        run_cmd("npm uninstall -g @qingchencloud/openclaw-zh", timeout=30)
        run_cmd("npm uninstall -g openclaw", timeout=30)
        
        # 安装
        out, err, rc = run_cmd(f'npm install -g openclaw@{latest_ver}', timeout=180)
        if rc != 0:
            out, err, rc = run_cmd('npm install -g openclaw@latest', timeout=180)
        
        if rc != 0:
            return {"ok": False, "msg": f"npm 安装失败: {err[:150]}"}
        
        # 初始化
        init_result = self._init_openclaw_after_install()
        
        return {
            "ok": True,
            "msg": f"原版安装完成" + ("（已初始化配置）" if init_result else ""),
            "version": latest_ver if latest_ver != "latest" else ""
        }

    def _init_openclaw_after_install(self):
        """安装后初始化 OpenClaw 配置"""
        try:
            oc = find_openclaw_cmd()
            if not oc:
                return False
            
            # 检查是否已有配置文件
            config_path = find_local_config()
            if config_path:
                return True  # 已有配置，跳过
            
            # 默认配置路径
            home = Path.home()
            if PLATFORM == "Windows":
                cfg_dir = home / ".openclaw"
            elif PLATFORM == "Darwin":
                cfg_dir = home / ".openclaw"
            else:
                cfg_dir = home / ".openclaw"
            
            cfg_dir.mkdir(parents=True, exist_ok=True)
            cfg_path = cfg_dir / "openclaw.json"
            
            if cfg_path.exists():
                return True
            
            # 写入默认配置
            default_cfg = {
                "gateway": {
                    "port": 18789,
                    "token": secrets.token_urlsafe(24)
                },
                "models": {
                    "providers": {}
                },
                "meta": {
                    "lastTouchedVersion": ""
                }
            }
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(default_cfg, f, indent=2, ensure_ascii=False)
            
            return True
        except:
            return False

    def get_install_options(self, version_type="original"):
        """获取指定版本的可用安装方式"""
        options = []
        
        if version_type == "chinese":
            # 中文版只能通过 npm 安装
            has_node = shutil.which("node") is not None
            has_npm = shutil.which("npm") is not None
            options.append({
                "method": "npm",
                "label": "npm 安装",
                "desc": "npm install -g @qingchencloud/openclaw-zh",
                "available": has_node and has_npm,
                "need_msg": "需要 Node.js + npm" if not (has_node and has_npm) else ""
            })
        else:
            # 原版：Docker（优先）或 npm
            has_docker = shutil.which("docker") is not None
            has_npm = shutil.which("npm") is not None
            
            options.append({
                "method": "docker",
                "label": "Docker 容器",
                "desc": "推荐，一键部署，环境隔离",
                "available": has_docker,
                "need_msg": "需要安装 Docker Desktop" if not has_docker else ""
            })
            if has_npm:
                options.append({
                    "method": "npm",
                    "label": "npm 安装",
                    "desc": "npm install -g openclaw",
                    "available": True,
                    "need_msg": ""
                })
        
        return {"ok": True, "options": options}

    def check_openclaw_update(self):
        """检查 OpenClaw 更新（使用 HTTP API）"""
        current_version = self._get_current_openclaw_version()
        version_type = self._detect_openclaw_version_type()
        
        try:
            import requests as req_lib
            
            if version_type == "chinese":
                label = "中文版"
                r = req_lib.get("https://registry.npmjs.org/@qingchencloud/openclaw-zh/latest", timeout=10)
                if r.status_code == 200:
                    latest_version = r.json().get("version", "")
                    published_at = ""
                else:
                    return {"ok": False, "msg": "获取版本信息失败"}
            else:
                label = "原版"
                r = req_lib.get("https://hub.docker.com/v2/repositories/openclaw/openclaw/tags?page_size=5", timeout=10)
                if r.status_code == 200:
                    tags = r.json().get("results", [])
                    latest_version = ""
                    published_at = ""
                    for t in tags:
                        name = t.get("name", "")
                        if name != "nightly" and not name.startswith("sha256"):
                            latest_version = name
                            published_at = t.get("last_updated", "")
                            break
                    if not latest_version:
                        return {"ok": False, "msg": "未找到版本信息"}
                else:
                    r = req_lib.get("https://api.github.com/repos/openclaw/openclaw/releases/latest", timeout=10)
                    if r.status_code == 200:
                        data = r.json()
                        latest_version = data.get("tag_name", "")
                        published_at = data.get("published_at", "")
                    else:
                        return {"ok": False, "msg": "获取版本信息失败"}
        except Exception as e:
            return {"ok": False, "msg": f"获取版本信息失败: {str(e)}"}
        
        has_update = False
        if current_version and latest_version:
            has_update = current_version != latest_version
        
        return {
            "ok": True,
            "current_version": current_version or "未知",
            "latest_version": latest_version,
            "version_type": label,
            "has_update": has_update,
            "published_at": published_at
        }

    def _get_current_openclaw_version(self):
        """获取当前 OpenClaw 版本"""
        # 尝试从配置文件读取
        config_path = find_local_config()
        if config_path:
            cfg = _read_json(config_path)
            version = cfg.get('meta', {}).get('lastTouchedVersion', '')
            if version:
                return version
        
        # 尝试从命令行获取
        if shutil.which('openclaw'):
            out, _, rc = run_cmd('openclaw --version', timeout=5)
            if rc == 0 and out.strip():
                return out.strip()
        
        return None

    def _detect_openclaw_version_type(self):
        """检测 OpenClaw 版本类型（原版或中文版）"""
        # 检查 npm 全局安装的包
        out, _, rc = run_cmd("npm list -g --depth=0", timeout=10)
        if rc == 0:
            if "@qingchencloud/openclaw-zh" in out:
                return "chinese"
            if "openclaw" in out:
                return "original"
        
        # 检查 openclaw --version 输出
        oc = find_openclaw_cmd()
        if oc:
            out, _, rc = run_cmd(f'"{oc}" --version', timeout=5)
            if rc == 0 and "-zh" in out.lower():
                return "chinese"
        
        return "original"

    def uninstall_openclaw(self):
        """卸载 OpenClaw - 按官方方式"""
        messages = []
        uninstalled = False
        
        # 1. 停止运行中的进程
        if PLATFORM == "Windows":
            # 停止计划任务
            run_cmd('schtasks /End /TN "OpenClaw Gateway"', timeout=5)
            # 杀死所有 openclaw 相关进程
            run_cmd('taskkill /F /IM node.exe /FI "WINDOWTITLE eq openclaw*"', timeout=5)
            # 通过端口查找并杀死进程
            out, _, _ = run_cmd('netstat -ano | findstr :18789 | findstr LISTENING', timeout=5)
            if out:
                for line in out.strip().split('\n'):
                    parts = line.split()
                    if len(parts) >= 5:
                        pid = parts[-1]
                        run_cmd(f'taskkill /F /PID {pid}', timeout=5)
        else:
            run_cmd('pkill -f openclaw', timeout=5)
        
        # 2. 卸载 npm 包（中文版）
        out1, err1, rc1 = run_cmd("npm uninstall -g @qingchencloud/openclaw-zh", timeout=30)
        if rc1 == 0:
            uninstalled = True
            messages.append("已卸载中文汉化版")
        
        # 3. 卸载 npm 包（原版）
        out2, err2, rc2 = run_cmd("npm uninstall -g openclaw", timeout=30)
        if rc2 == 0:
            uninstalled = True
            messages.append("已卸载原版 OpenClaw")
        
        # 4. 清理计划任务（Windows）
        if PLATFORM == "Windows":
            run_cmd('schtasks /Delete /TN "OpenClaw Gateway" /F', timeout=5)
            # 清理 gateway.cmd 和 gateway.vbs
            gateway_cmd = Path.home() / ".openclaw" / "gateway.cmd"
            gateway_vbs = Path.home() / ".openclaw" / "gateway.vbs"
            if gateway_cmd.exists():
                try:
                    gateway_cmd.unlink()
                    messages.append("已清理 gateway.cmd")
                except:
                    pass
            if gateway_vbs.exists():
                try:
                    gateway_vbs.unlink()
                    messages.append("已清理 gateway.vbs")
                except:
                    pass
        
        # 5. 检查是否还有 openclaw 命令
        check_out, _, check_rc = run_cmd("openclaw --version", timeout=5)
        if check_rc == 0:
            messages.append(f"警告: openclaw 命令仍存在 ({check_out.strip()})")
        
        # 6. Docker 容器清理（可选）
        docker_out, _, docker_rc = run_cmd("docker ps -a --filter name=openclaw --format {{.Names}}", timeout=5)
        if docker_rc == 0 and docker_out.strip():
            for name in docker_out.strip().split("\n"):
                name = name.strip()
                if name:
                    run_cmd(f"docker stop {name}", timeout=10)
                    run_cmd(f"docker rm {name}", timeout=10)
                    uninstalled = True
                    messages.append(f"已删除 Docker 容器: {name}")
        
        if uninstalled:
            return {"ok": True, "msg": "；".join(messages) if messages else "卸载完成"}
        
        return {"ok": False, "msg": "未检测到 OpenClaw 安装"}


# ============================================================
#  启动
# ============================================================

def set_window_icon(window):
    """设置窗口图标"""
    try:
        icon_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui", "icon.ico")
        if not os.path.exists(icon_path):
            return

        if PLATFORM == "Windows":
            import ctypes
            time.sleep(1.5)

            hwnd = None
            if hasattr(window, "native_handle") and window.native_handle:
                hwnd = window.native_handle
            elif hasattr(window, "_hwnd"):
                hwnd = window._hwnd
            else:
                EnumWindows = ctypes.windll.user32.EnumWindows
                EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.c_int)
                GetWindowText = ctypes.windll.user32.GetWindowTextW
                GetWindowTextLength = ctypes.windll.user32.GetWindowTextLengthW

                result = []

                def enum_cb(hwnd_win, _):
                    length = GetWindowTextLength(hwnd_win)
                    if length > 0:
                        buff = ctypes.create_unicode_buffer(length + 1)
                        GetWindowText(hwnd_win, buff, length + 1)
                        if "AI坤" in buff.value:
                            result.append(hwnd_win)
                    return True

                EnumWindows(EnumWindowsProc(enum_cb), 0)
                if result:
                    hwnd = result[0]

            if hwnd:
                WM_SETICON = 0x0080
                IMAGE_ICON = 1
                LR_LOADFROMFILE = 0x0010
                icon = ctypes.windll.user32.LoadImageW(0, icon_path, IMAGE_ICON, 0, 0, LR_LOADFROMFILE)
                if icon:
                    ctypes.windll.user32.SendMessageW(hwnd, WM_SETICON, 0, icon)
                    ctypes.windll.user32.SendMessageW(hwnd, WM_SETICON, 1, icon)

    except Exception as e:
        print(f"设置图标失败: {e}")


def main():
    bridge = ApiBridge()
    ui_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui")
    html_path = os.path.join(ui_dir, "index.html")

    with open(html_path, "r", encoding="utf-8") as f:
        html = f.read()

    window = webview.create_window(
        title="AI坤 × OpenClaw 管理工具",
        html=html,
        js_api=bridge,
        width=1100,
        height=720,
        min_size=(900, 600),
        resizable=True,
        text_select=True,
    )

    webview.start(set_window_icon, window, debug=False)


if __name__ == "__main__":
    main()

