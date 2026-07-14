#!/bin/bash
# ============================================================
#  AI坤 × OpenClaw 管理工具  v1.0
#  唯一绑定: https://aikun.cnzc.qzz.io/v1
#  适配: 群晖 DSM / Linux / Docker
#  使用: sudo bash aikun.sh --install   # 安装
#        aikun                          # 运行管理
# ============================================================

set -euo pipefail

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- 常量 ----
readonly AIKUN_BASE="https://aikun.cnzc.qzz.io/v1"
readonly SCRIPT_VER="1.0.0"
readonly CACHE_DIR="${HOME}/.aikun-manager"
readonly CACHE_FILE="${CACHE_DIR}/cache"
readonly LOG_FILE="${CACHE_DIR}/manager.log"
readonly INSTALL_TARGET="/usr/local/bin/aikun"

# ---- 辅助函数：所有 OpenClaw 操作走 Docker 容器 ----
DOCKER_MODE=false
DOCKER_CONTAINER=""
API_KEY=""

docker_do() {
    if $DOCKER_MODE && [ -n "$DOCKER_CONTAINER" ] && [ "$DOCKER_CONTAINER" != "compose" ]; then
        docker exec "$DOCKER_CONTAINER" "$@"
    else
        "$@"
    fi
}

oc_do() {
    if $DOCKER_MODE && [ -n "$DOCKER_CONTAINER" ] && [ "$DOCKER_CONTAINER" != "compose" ]; then
        docker exec "$DOCKER_CONTAINER" openclaw "$@"
    else
        openclaw "$@"
    fi
}

oc_python() {
    if $DOCKER_MODE && [ -n "$DOCKER_CONTAINER" ] && [ "$DOCKER_CONTAINER" != "compose" ]; then
        docker exec -i "$DOCKER_CONTAINER" python3 -c "$@"
    else
        python3 -c "$@"
    fi
}

# ---- 容器内 JSON 配置操作 ----
config_path() {
    if $DOCKER_MODE && [ -n "$DOCKER_CONTAINER" ] && [ "$DOCKER_CONTAINER" != "compose" ]; then
        echo "/home/node/.openclaw/openclaw.json"
    else
        echo "${HOME}/.openclaw/openclaw.json"
    fi
}

read_container_config() {
    local cfg
    if $DOCKER_MODE && [ -n "$DOCKER_CONTAINER" ] && [ "$DOCKER_CONTAINER" != "compose" ]; then
        cfg=$(docker exec "$DOCKER_CONTAINER" cat "$(config_path)" 2>/dev/null)
        if [ -z "$cfg" ]; then
            # 容器已退出，用 docker cp 读取
            local tmp
            tmp=$(mktemp)
            cfg=$(docker cp "$DOCKER_CONTAINER:$(config_path)" "$tmp" 2>/dev/null && cat "$tmp" || echo "{}")
            rm -f "$tmp"
        fi
    elif [ -f "$(config_path)" ]; then
        cfg=$(cat "$(config_path)")
    else
        cfg="{}"
    fi
    [ -z "$cfg" ] && cfg="{}"
    echo "$cfg"
}

write_container_config() {
    local content="$1"
    local path
    path=$(config_path)
    if $DOCKER_MODE && [ -n "$DOCKER_CONTAINER" ] && [ "$DOCKER_CONTAINER" != "compose" ]; then
        # 先试 docker exec（容器运行中）
        if echo "$content" | docker exec -i "$DOCKER_CONTAINER" tee "$path" > /dev/null 2>&1; then
            return 0
        fi
        # 容器已退出，用 docker cp 写入
        local tmp
        tmp=$(mktemp)
        echo "$content" > "$tmp"
        docker cp "$tmp" "$DOCKER_CONTAINER:$path" 2>/dev/null
        local rc=$?
        rm -f "$tmp"
        return $rc
    else
        mkdir -p "$(dirname "$path")"
        echo "$content" > "$path"
    fi
}

# ---- 工具函数 ----
log_msg() {
    local level="$1" msg="$2"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${ts}] [${level}] ${msg}" >> "${LOG_FILE}" 2>/dev/null || true
}

info()  { echo -e "${GREEN}${*}${NC}"; }
warn()  { echo -e "${YELLOW}${*}${NC}"; }
error() { echo -e "${RED}${*}${NC}"; }
header(){ echo -e "${CYAN}${BOLD}${*}${NC}"; }

press_any_key() {
    echo ""
    echo -ne "${YELLOW}按回车键返回菜单...${NC}"
    read -r
}

print_banner() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   ${BOLD}AI坤 × OpenClaw 管理工具${NC}${CYAN}          ║${NC}"
    echo -e "${CYAN}║        版本 ${SCRIPT_VER}               ║${NC}"
    echo -e "${CYAN}║   ─────────────────────────────────   ║${NC}"
    echo -e "${CYAN}║   绑定: ${AIKUN_BASE}${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

print_status_bar() {
    local status_str=""
    if [ -n "$API_KEY" ]; then
        local masked="${API_KEY:0:8}****"
        status_str="${GREEN}✅ 已配置${NC}"
    else
        status_str="${RED}❌ 未配置${NC}"
    fi

    local mode_str="直装"
    if $DOCKER_MODE; then
        mode_str="Docker (${DOCKER_CONTAINER})"
    fi

    # 从容器读取模型数量
    local model_count=0
    local default_model="未设置"
    local models_summary=""
    local cfg
    cfg=$(read_container_config)
    if [ -n "$cfg" ] && command -v python3 >/dev/null 2>&1; then
        model_count=$(echo "$cfg" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    ms = d.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
    print(len(ms))
except: print(0)
" 2>/dev/null || echo "0")
        default_model=$(echo "$cfg" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','未设置'))
except: print('未设置')
" 2>/dev/null || echo "未设置")
        models_summary=$(echo "$cfg" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    ms = d.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
    def fmt(n):
        try: n=int(n)
        except: return str(n)
        if n >= 1000000: return f'{n//1000000}M'
        if n >= 1000: return f'{n//1000}K'
        return str(n)
    parts = []
    for m in ms:
        cw = m.get('contextWindow','?')
        mt = m.get('maxTokens','?')
        try: cw_s = fmt(int(cw))
        except: cw_s = str(cw)
        parts.append(f'{m["id"]}(ctx:{cw_s}/out:{mt})')
    print(' | '.join(parts))
except: print('')
" 2>/dev/null || echo "")
    fi

    echo -e " ${BLUE}API Key:${NC}  ${status_str}"
    echo -e " ${BLUE}运行模式:${NC} ${mode_str}"
    echo -e " ${BLUE}已启用:${NC}   ${model_count} 个模型"
    if [ -n "$models_summary" ]; then
        echo -e " ${BLUE}模型详情:${NC}"
        echo "$models_summary" | sed 's/^/    /'
    fi
    echo -e " ${BLUE}默认模型:${NC} ${default_model}"
    echo ""
}

confirm_action() {
    local prompt="$1"
    echo -ne "${YELLOW}${prompt} [y/N]: ${NC}"
    read -r ans
    case "$ans" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

cleanup_and_exit() {
    echo ""
    echo -e "${GREEN}感谢使用 AI坤 × OpenClaw 管理工具！${NC}"
    exit 0
}

json_extract() {
    # 从 JSON 字符串中提取指定路径的值
    local json="$1" expr="$2"
    echo "$json" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    val = $expr
    if val is None: sys.exit(1)
    print(val)
except: sys.exit(1)
" 2>/dev/null || return 1
}

# ============================================================
#  安装模式
# ============================================================

do_install() {
    echo ""
    header "🔧 AI坤 × OpenClaw 管理工具 — 安装"
    echo "  ─────────────────────────────────"
    echo ""

    local install_ok=true

    # 1. 检查 root 权限
    echo -ne "  ${BLUE}检查 root 权限...${NC}"
    if [ "$(id -u)" -eq 0 ]; then
        echo -e " ${GREEN}✅${NC}"
    else
        echo -e " ${YELLOW}⚠️  需要 root 权限${NC}"
        echo "  请使用 sudo 或 su root 重新运行:"
        echo "    sudo bash $0 --install"
        exit 1
    fi

    # 2. 检查系统类型
    echo -ne "  ${BLUE}检测系统类型...${NC}"
    local is_synology=false
    if [ -f "/etc/synoinfo.conf" ] || [ -d "/volume1" ]; then
        is_synology=true
        echo -e " ${YELLOW}群晖 DSM${NC}"
    else
        echo -e " ${GREEN}$(uname -s)${NC}"
    fi

    # 3. 检查/安装依赖
    echo ""
    header "  依赖检查"
    echo "  ─────────────────────────────────"

    # curl
    echo -ne "    curl..."
    if command -v curl >/dev/null 2>&1; then
        echo -e " ${GREEN}✅ $(curl --version | head -1 | awk '{print $2}')${NC}"
    else
        echo -e " ${YELLOW}❌ 未安装${NC}"
        echo -ne "    正在安装 curl..."
        if $is_synology; then
            # 群晖安装 curl
            if command -v synopkg >/dev/null 2>&1; then
                synopkg install curl >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || {
                    echo -e " ${RED}❌${NC}"
                    warn "    请通过套件中心安装 curl"
                    install_ok=false
                }
            else
                echo -e " ${RED}❌${NC}"
                warn "    请安装 curl: sudo synopkg install curl"
                install_ok=false
            fi
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get install -y curl >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || {
                echo -e " ${RED}❌${NC}"; install_ok=false; }
        else
            echo -e " ${RED}❌${NC}"
            warn "    请手动安装 curl"
            install_ok=false
        fi
    fi

    # python3
    echo -ne "    python3..."
    if command -v python3 >/dev/null 2>&1; then
        echo -e " ${GREEN}✅ $(python3 --version 2>&1 | awk '{print $2}')${NC}"
    else
        echo -e " ${YELLOW}❌ 未安装${NC}"
        echo -ne "    正在安装 python3..."
        if $is_synology; then
            if command -v synopkg >/dev/null 2>&1; then
                synopkg install Python3 >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || {
                    echo -e " ${RED}❌${NC}"
                    warn "    请通过套件中心安装 Python 3"
                    install_ok=false
                }
            else
                echo -e " ${RED}❌${NC}"
                warn "    请安装 Python 3"
                install_ok=false
            fi
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get install -y python3 >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || {
                echo -e " ${RED}❌${NC}"; install_ok=false; }
        else
            echo -e " ${RED}❌${NC}"
            warn "    请手动安装 python3"
            install_ok=false
        fi
    fi

    # jq（可选）
    echo -ne "    jq..."
    if command -v jq >/dev/null 2>&1; then
        echo -e " ${GREEN}✅${NC}"
    else
        echo -e " ${YELLOW}❌ (可选)${NC}"
    fi

    # docker
    echo -ne "    docker..."
    if command -v docker >/dev/null 2>&1; then
        echo -e " ${GREEN}✅ $(docker --version 2>&1 | awk '{print $3}' | tr -d ',')${NC}"
    else
        echo -e " ${YELLOW}❌ 未安装${NC}"
        warn "    OpenClaw 需要 Docker，请安装 Docker 套件"
        if $is_synology; then
            echo "    群晖请在套件中心安装 Docker"
        fi
    fi

    echo ""

    # 4. 安装脚本到系统 PATH
    header "  安装脚本"
    echo "  ─────────────────────────────────"

    local script_path="$0"
    # 如果是通过管道或 curl 运行的，$0 可能是 bash，需要特殊处理
    if [ ! -f "$script_path" ] || [[ "$script_path" == "bash" ]]; then
        script_path="$(pwd)/aikun.sh"
    fi

    echo -ne "    复制到 ${INSTALL_TARGET}..."
    if [ -f "$script_path" ]; then
        cp "$script_path" "$INSTALL_TARGET" 2>/dev/null && {
            chmod 755 "$INSTALL_TARGET"
            echo -e " ${GREEN}✅${NC}"
        } || {
            echo -e " ${RED}❌${NC}"
            warn "    复制失败，请手动执行:"
            warn "    cp aikun.sh ${INSTALL_TARGET} && chmod 755 ${INSTALL_TARGET}"
            install_ok=false
        }
    else
        echo -e " ${YELLOW}⚠️  找不到脚本文件${NC}"
        warn "    请手动复制: cp aikun.sh ${INSTALL_TARGET}"
    fi

    # 5. 检测 OpenClaw Docker 容器
    echo ""
    header "  检测 OpenClaw"
    echo "  ─────────────────────────────────"

    if command -v docker >/dev/null 2>&1; then
        local container
        container=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -i openclaw | head -1 || true)
        if [ -n "$container" ]; then
            local running
            running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i openclaw | head -1 || true)
            if [ -n "$running" ]; then
                echo -e "    OpenClaw: ${GREEN}运行中${NC} ($container)"
            else
                echo -e "    OpenClaw: ${YELLOW}容器已停止${NC} ($container)"
                echo -e "    启动命令: ${CYAN}docker start $container${NC}"
            fi
        else
            echo -e "    OpenClaw: ${YELLOW}未检测到容器${NC}"
            echo "    请先部署 OpenClaw:"
            echo "    docker run -d --name openclaw --restart unless-stopped \\"
            echo "      -p 18790:18790 \\"
            echo "      -v /path/to/config:/home/node/.openclaw \\"
            echo "      openclaw/openclaw:latest gateway --port 18790"
        fi
    else
        echo -e "    OpenClaw: ${YELLOW}Docker 不可用，跳过检测${NC}"
    fi

    echo ""

    # 6. 权限加固
    header "  权限设置"
    echo "  ─────────────────────────────────"
    if [ -f "$INSTALL_TARGET" ]; then
        chmod 755 "$INSTALL_TARGET"
        echo -e "    ${INSTALL_TARGET}: ${GREEN}755${NC}"
        # 群晖特殊权限处理
        if $is_synology; then
            chown root:root "$INSTALL_TARGET" 2>/dev/null || true
            echo -e "    所有者: ${GREEN}root${NC}"
        fi
    fi

    echo ""

    # 7. 结果汇总
    if $install_ok; then
        info "  ✅ 安装完成！"
        echo ""
        echo "  现在可以:"
        echo "    1) 直接输入 ${CYAN}aikun${NC} 启动管理工具"
        echo "    2) 首次使用会自动进入初始化引导"
        echo "    3) 如果提示命令不存在，请重新登录 SSH 或执行:"
        echo "       ${CYAN}hash -r; aikun${NC}"
    else
        warn "  ⚠️  安装完成，但部分步骤需要手动处理"
        echo "  请根据以上提示完成剩余配置"
    fi

    echo ""
}

# ============================================================
#  环境检测
# ============================================================

detect_openclaw_mode() {
    DOCKER_MODE=false
    DOCKER_CONTAINER=""

    # 检测运行中的 Docker 容器
    local container
    container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i openclaw | head -1 || true)
    if [ -n "$container" ]; then
        DOCKER_MODE=true
        DOCKER_CONTAINER="$container"
        return 0
    fi

    # 检测已停机的 Docker 容器
    container=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -i openclaw | head -1 || true)
    if [ -n "$container" ]; then
        DOCKER_MODE=true
        DOCKER_CONTAINER="$container"
        return 0
    fi

    return 1
}

read_api_key() {
    API_KEY=""
    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")
    if [ -n "$cfg" ] && command -v python3 >/dev/null 2>&1; then
        API_KEY=$(echo "$cfg" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    print(d.get('models',{}).get('providers',{}).get('aikun',{}).get('apiKey',''))
except: pass
" 2>/dev/null || true)
    fi

    # 从缓存读取兜底
    if [ -z "$API_KEY" ] && [ -f "$CACHE_FILE" ]; then
        API_KEY=$(grep "^API_KEY=" "$CACHE_FILE" 2>/dev/null | cut -d= -f2- || true)
    fi
}

save_cache() {
    mkdir -p "$CACHE_DIR"
    cat > "$CACHE_FILE" <<-EOF
API_KEY=${API_KEY}
LAST_UPDATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# ============================================================
#  API 操作
# ============================================================

fetch_model_list() {
    local key="$1"
    if [ -z "$key" ]; then
        error "❌ 请先配置 API Key"
        return 1
    fi

    echo -ne "  ${BLUE}正在从 AI坤 API 拉取模型列表..." >&2
    local result
    result=$(curl -s -w "\n%{http_code}" "${AIKUN_BASE}/models" \
        -H "Authorization: Bearer ${key}" \
        --connect-timeout 10 --max-time 15 2>/dev/null || true)

    local http_code
    http_code=$(echo "$result" | tail -1)
    local body
    body=$(echo "$result" | sed '$d')

    if [ "$http_code" != "200" ]; then
        echo -e " ${RED}❌${NC}" >&2
        error "   API 返回状态码: ${http_code}"
        local err_msg
        err_msg=$(echo "$body" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message','未知错误'))" 2>/dev/null || echo "连接失败")
        error "   错误: ${err_msg}"
        return 1
    fi

    echo -e " ${GREEN}✅${NC}" >&2

    local model_json
    model_json=$(echo "$body" | python3 -c "
import json,sys
d = json.load(sys.stdin)
models = d.get('data', [])
for m in models:
    mid = m.get('id','')
    owned_by = m.get('owned_by','')
    cw = m.get('contextWindow', m.get('context_window', m.get('max_context_length', '')))
    mt = m.get('maxTokens', m.get('max_tokens', m.get('max_output_tokens', '')))
    print(f'{mid}|{owned_by}|{cw}|{mt}')
" 2>/dev/null || true)

    if [ -z "$model_json" ]; then
        error "❌ 未能解析模型列表"
        return 1
    fi

    echo "$model_json"
    return 0
}

test_connection() {
    local key="$1"
    [ -z "$key" ] && return 1

    echo -ne "  ${BLUE}测试 AI坤 API 连通性..." >&2
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${AIKUN_BASE}/models" \
        -H "Authorization: Bearer ${key}" \
        --connect-timeout 8 --max-time 12 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
        echo -e " ${GREEN}✅${NC}" >&2
        return 0
    else
        echo -e " ${RED}❌ (HTTP ${http_code})${NC}" >&2
        return 1
    fi
}

# ============================================================
#  配置操作（读写容器内 JSON）
# ============================================================

backup_config() {
    local bak_dir="${CACHE_DIR}/backups"
    mkdir -p "$bak_dir"
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    local backup_path="${bak_dir}/openclaw.json.${ts}"

    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")
    if [ "$cfg" != "{}" ]; then
        echo "$cfg" > "$backup_path"
        info "✅ 配置已备份: ${backup_path}"
        log_msg "INFO" "配置备份: ${backup_path}"
    else
        warn "⚠️  没有找到配置可以备份"
    fi
}

list_backups() {
    local bak_dir="${CACHE_DIR}/backups"
    if [ ! -d "$bak_dir" ]; then
        warn "  暂无备份"
        return 1
    fi
    local backups=("$bak_dir"/*)
    if [ ${#backups[@]} -eq 0 ] || [ ! -f "${backups[0]}" ]; then
        warn "  暂无备份"
        return 1
    fi
    local i=1
    for b in "${backups[@]}"; do
        local fname size ts
        fname=$(basename "$b")
        size=$(stat -c%s "$b" 2>/dev/null || stat -f%z "$b" 2>/dev/null || echo "0")
        ts=$(stat -c%y "$b" 2>/dev/null || stat -f%Sm "$b" 2>/dev/null || echo "")
        echo "   ${i}) ${fname}  (${size}B)  ${ts}"
        i=$((i+1))
    done
    return 0
}

restore_backup() {
    local bak_dir="${CACHE_DIR}/backups"
    if [ ! -d "$bak_dir" ]; then
        warn "  暂无备份可恢复"
        press_any_key
        return 1
    fi

    local backups=("$bak_dir"/*)
    if [ ${#backups[@]} -eq 0 ] || [ ! -f "${backups[0]}" ]; then
        warn "  暂无备份可恢复"
        press_any_key
        return 1
    fi

    echo ""
    header "💾 选择要恢复的备份:"
    local i=1
    declare -A BACKUP_MAP
    for b in "${backups[@]}"; do
        local fname
        fname=$(basename "$b")
        echo "   ${i}) ${fname}"
        BACKUP_MAP[$i]="$b"
        i=$((i+1))
    done
    echo "   0) 取消"

    echo -ne "\n  请输入编号 [0-${i}]: "
    read -r choice
    [ "$choice" = "0" ] || [ -z "$choice" ] && return 1

    local selected="${BACKUP_MAP[$choice]}"
    if [ -z "$selected" ] || [ ! -f "$selected" ]; then
        error "❌ 无效选择"
        press_any_key
        return 1
    fi

    if confirm_action "⚠️  确定要恢复此备份？"; then
        backup_config
        local content
        content=$(cat "$selected")
        write_container_config "$content"
        info "✅ 已恢复备份: $(basename "$selected")"
        log_msg "INFO" "配置恢复自: $(basename "$selected")"
        echo -e "${YELLOW}  需要重启 OpenClaw 使配置生效。${NC}"
    fi
    press_any_key
}

write_aikun_config() {
    local api_key="$1" models_json="$2" default_model="$3"
    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")

    # 用 python 修改 JSON
    local new_cfg
    new_cfg=$(echo "$cfg" | python3 -c "
import json,sys
cfg = json.load(sys.stdin)

# ========== 模型知识库 ==========
MODEL_DB = {
    # ── DeepSeek ──
    'deepseek-v4-flash':    {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-v4-pro':      {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-v4':          {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-r1':          {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-chat':        {'contextWindow': 65536,   'maxTokens': 8192},
    'deepseek-coder':       {'contextWindow': 65536,   'maxTokens': 8192},
    'deepseek-v3':          {'contextWindow': 65536,   'maxTokens': 8192},
    # ── Kimi (月之暗面) ──
    'kimi-k2.7-code':       {'contextWindow': 1048576, 'maxTokens': 8192},
    'kimi-k2.6':            {'contextWindow': 262144,  'maxTokens': 8192},
    'kimi-k2.5':            {'contextWindow': 262144,  'maxTokens': 8192},
    # ── MiniMax ──
    'minimax-m3':           {'contextWindow': 1048576, 'maxTokens': 8192},
    'minimax-m2.5':         {'contextWindow': 1048576, 'maxTokens': 8192},
    # ── Qwen (通义千问) ──
    'qwen3.7-max':          {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen3.7-plus':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen3.6-plus':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen3.5-plus':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen-max':             {'contextWindow': 32768,   'maxTokens': 8192},
    'qwen-plus':            {'contextWindow': 131072,  'maxTokens': 8192},
    'qwen-turbo':           {'contextWindow': 131072,  'maxTokens': 8192},
    'qwen-long':            {'contextWindow': 10000000, 'maxTokens': 6000},
    # ── GLM (智谱) ──
    'glm-5.2':              {'contextWindow': 131072,  'maxTokens': 8192},
    'glm-5':                {'contextWindow': 131072,  'maxTokens': 8192},
    # ── 豆包 ──
    'doubao-seed-2.0-pro':  {'contextWindow': 262144,  'maxTokens': 16384},
    'doubao-seed-2.0-code': {'contextWindow': 262144,  'maxTokens': 16384},
    # ── GPT (OpenAI) ──
    'gpt-5':                {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-5.5':              {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-5.4':              {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-5.3-codex':        {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-4o':               {'contextWindow': 128000,  'maxTokens': 16384},
    'gpt-4o-mini':          {'contextWindow': 128000,  'maxTokens': 16384},
    'gpt-4-turbo':          {'contextWindow': 128000,  'maxTokens': 4096},
    'gpt-4':                {'contextWindow': 8192,    'maxTokens': 8192},
    'gpt-3.5-turbo':        {'contextWindow': 16385,   'maxTokens': 4096},
    'o1':                   {'contextWindow': 200000,  'maxTokens': 100000},
    'o1-mini':              {'contextWindow': 128000,  'maxTokens': 65536},
    'o1-preview':           {'contextWindow': 128000,  'maxTokens': 32768},
    'o3-mini':              {'contextWindow': 200000,  'maxTokens': 100000},
    # ── Claude (Anthropic) ──
    'claude-opus-4.8':      {'contextWindow': 1048576, 'maxTokens': 131072},
    'claude-sonnet-4.6':    {'contextWindow': 1048576, 'maxTokens': 131072},
    'claude-opus-4.1':      {'contextWindow': 200000,  'maxTokens': 32768},
    'claude-3.5-sonnet':    {'contextWindow': 200000,  'maxTokens': 8192},
    'claude-3.5-haiku':     {'contextWindow': 200000,  'maxTokens': 8192},
    'claude-3-opus':        {'contextWindow': 200000,  'maxTokens': 4096},
    'claude-3-sonnet':      {'contextWindow': 200000,  'maxTokens': 4096},
    'claude-3-haiku':       {'contextWindow': 200000,  'maxTokens': 4096},
    # ── Gemini (Google) ──
    'gemini-3-pro':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-3.1-pro':       {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-3.5-flash':     {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-2.5-pro':       {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-2.5-flash':     {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-2.0-flash':     {'contextWindow': 1048576, 'maxTokens': 8192},
    'gemini-1.5-pro':       {'contextWindow': 2000000, 'maxTokens': 8192},
    'gemini-1.5-flash':     {'contextWindow': 1048576, 'maxTokens': 8192},
    # ── Llama (Meta) ──
    'llama-4-maverick':     {'contextWindow': 1048576, 'maxTokens': 8192},
    'llama-4-scout':        {'contextWindow': 10000000, 'maxTokens': 8192},
    # ── Grok (xAI) ──
    'grok-4.1':             {'contextWindow': 1048576, 'maxTokens': 32768},
}

# 解析传入的模型列表
models_list = json.loads('${models_json}')

# 尝试从 GitHub 获取模型参数（国际模型）
def fetch_model_params(mid):
    import urllib.request, urllib.error
    provider_map = {
        'gpt': 'openai', 'o1': 'openai', 'o3': 'openai',
        'claude': 'anthropic',
        'gemini': 'google-gemini',
        'grok': 'xai',
        'mistral': 'mistral', 'mixtral': 'mistral',
    }
    prefix = mid.split('-')[0].split('.')[0].lower()
    provider = provider_map.get(prefix)
    if not provider:
        return None
    filename = mid.replace('.', '-')
    url = f'https://raw.githubusercontent.com/truefoundry/models/main/providers/{provider}/{filename}.yaml'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'aikun-manager/1.0'})
        with urllib.request.urlopen(req, timeout=5) as r:
            content = r.read().decode()
            ctx = out = None
            for line in content.split('\n'):
                line = line.strip()
                if line.startswith('context_window:'):
                    ctx = int(line.split(':')[1].strip())
                elif line.startswith('max_output_tokens:'):
                    out = int(line.split(':')[1].strip())
            if ctx:
                return {'contextWindow': ctx, 'maxTokens': out or 4096}
    except:
        pass
    return None

# 补充 contextWindow / maxTokens（远程优先 → 知识库 → 默认值）
for m in models_list:
    mid = m.get('id', '')
    if 'contextWindow' not in m or not m.get('contextWindow'):
        remote = fetch_model_params(mid)
        if remote:
            m['contextWindow'] = remote['contextWindow']
            m['maxTokens'] = remote.get('maxTokens', m.get('maxTokens', 4096))
        else:
            db = MODEL_DB.get(mid, {})
            m['contextWindow'] = db.get('contextWindow', 128000)
            m['maxTokens'] = db.get('maxTokens', 4096)
    if 'maxTokens' not in m or not m.get('maxTokens'):
        m['maxTokens'] = MODEL_DB.get(mid, {}).get('maxTokens', 4096)

# 设置 AI坤 供应商
cfg.setdefault('models',{})
cfg['models']['mode'] = 'merge'
cfg.setdefault('agents',{}).setdefault('defaults',{})
cfg['models'].setdefault('providers',{})
cfg['models']['providers']['aikun'] = {
    'baseUrl': '${AIKUN_BASE}',
    'apiKey': '${api_key}',
    'api': 'openai-completions',
    'models': models_list
}

# 设置 agents.models 允许列表
models_dict = {}
for m in models_list:
    models_dict[f'aikun/{m[\"id\"]}'] = {}
cfg['agents']['defaults']['models'] = models_dict

# 设置默认模型
if '${default_model}':
    cfg['agents']['defaults'].setdefault('model',{})['primary'] = f'aikun/${default_model}'

print(json.dumps(cfg, indent=2, ensure_ascii=False))
" 2>/dev/null) || return 1

    write_container_config "$new_cfg"
    log_msg "INFO" "AI坤 配置已写入"
    return 0
}

toggle_model() {
    local model_id="$1" action="$2"  # enable / disable
    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")
    local new_cfg
    new_cfg=$(echo "$cfg" | python3 -c "
import json,sys
cfg = json.load(sys.stdin)
models_list = cfg.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
agents_models = cfg.setdefault('agents',{}).setdefault('defaults',{}).setdefault('models',{})
model_key = f'aikun/${model_id}'

if '${action}' == 'enable':
    exists = any(m['id'] == '${model_id}' for m in models_list)
    if not exists:
        models_list.append({'id': '${model_id}', 'contextWindow': 128000, 'maxTokens': 4096})
        agents_models[model_key] = {}
    print('ENABLED')
else:
    cfg['models']['providers']['aikun']['models'] = [m for m in models_list if m['id'] != '${model_id}']
    agents_models.pop(model_key, None)
    current = cfg.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','')
    if current == model_key:
        remaining = list(agents_models.keys())
        cfg['agents']['defaults']['model']['primary'] = remaining[0] if remaining else ''
    print('DISABLED')

print('---JSON---')
print(json.dumps(cfg, indent=2, ensure_ascii=False))
" 2>/dev/null) || return 1

    local result
    result=$(echo "$new_cfg" | head -1)
    local json_part
    json_part=$(echo "$new_cfg" | sed -n '/^---JSON---$/, $ p' | tail -n +2)
    if [ -n "$json_part" ]; then
        write_container_config "$json_part"
    fi
    echo "$result"
    return 0
}

set_default_model() {
    local model_id="$1"
    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")
    local new_cfg
    new_cfg=$(echo "$cfg" | python3 -c "
import json,sys
cfg = json.load(sys.stdin)
cfg.setdefault('agents',{}).setdefault('defaults',{}).setdefault('model',{})['primary'] = f'aikun/${model_id}'
print(json.dumps(cfg, indent=2, ensure_ascii=False))
" 2>/dev/null) || return 1
    write_container_config "$new_cfg"
    return 0
}

# ============================================================
#  模型参数编辑
# ============================================================

edit_model_params() {
    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")
    local models_info
    models_info=$(echo "$cfg" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    models = d.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
    for i,m in enumerate(models,1):
        cw = m.get('contextWindow','?')
        mt = m.get('maxTokens','?')
        print(f'{i}|{m["id"]}|{cw}|{mt}')
except: pass
" 2>/dev/null) || { warn "  没有已启用的模型"; return 1; }

    echo ""
    header "✏️  编辑模型参数"
    echo "  ─────────────────────────────────"

    local i=1 model_ids=() model_cw=() model_mt=()
    while IFS='|' read -r idx mid cw mt; do
        [ -z "$mid" ] && continue
        model_ids+=("$mid")
        model_cw+=("$cw")
        model_mt+=("$mt")
        local cw_fmt
        if [ "$cw" != "?" ] && [ -n "$cw" ]; then
            if [ "$cw" -ge 1000000 ] 2>/dev/null; then
                cw_fmt="$(($cw / 1000000))M"
            elif [ "$cw" -ge 1000 ] 2>/dev/null; then
                cw_fmt="$(($cw / 1000))K"
            else
                cw_fmt="$cw"
            fi
        else
            cw_fmt="?"
        fi
        local mt_fmt
        if [ "$mt" != "?" ] && [ -n "$mt" ]; then
            mt_fmt="$mt"
        else
            mt_fmt="?"
        fi
        printf "  %d) %-30s  ctx: %-8s  out: %s\n" "$i" "$mid" "$cw_fmt" "$mt_fmt"
        i=$((i+1))
    done <<< "$models_info"

    [ ${#model_ids[@]} -eq 0 ] && { warn "  没有已启用的模型"; return 1; }

    echo ""
    echo -ne "  选择要编辑的模型编号: "
    read -r sel_idx
    local edit_i=$((sel_idx - 1))
    [ "$edit_i" -lt 0 ] || [ "$edit_i" -ge ${#model_ids[@]} ] && { error "❌ 无效选择"; return 1; }

    local target_id="${model_ids[$edit_i]}"
    local cur_cw="${model_cw[$edit_i]}"
    local cur_mt="${model_mt[$edit_i]}"
    [ "$cur_cw" = "?" ] && cur_cw=""
    [ "$cur_mt" = "?" ] && cur_mt=""

    echo ""
    echo "  编辑: ${target_id}"
    echo "  ──────────────────"
    echo -ne "  ContextWindow [${cur_cw:-128000}]: "
    read -r new_cw
    new_cw="${new_cw:-${cur_cw:-128000}}"

    echo -ne "  MaxTokens [${cur_mt:-4096}]: "
    read -r new_mt
    new_mt="${new_mt:-${cur_mt:-4096}}"

    local new_cfg
    new_cfg=$(echo "$cfg" | python3 -c "
import json,sys
cfg = json.load(sys.stdin)
models = cfg.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
for m in models:
    if m['id'] == '${target_id}':
        try:
            m['contextWindow'] = int('${new_cw}')
        except:
            m['contextWindow'] = 128000
        try:
            m['maxTokens'] = int('${new_mt}')
        except:
            m['maxTokens'] = 4096
print(json.dumps(cfg, indent=2, ensure_ascii=False))
" 2>/dev/null) || return 1

    write_container_config "$new_cfg" && info "✅ 模型参数已更新" || error "❌ 写入失败"
    return 0
}

# ============================================================
#  服务管理
# ============================================================

service_restart() {
    echo -ne "  ${BLUE}正在重启 OpenClaw..."
    if $DOCKER_MODE; then
        docker restart "$DOCKER_CONTAINER" 2>/dev/null || { error "❌"; return 1; }
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl restart openclaw 2>/dev/null || { error "❌"; return 1; }
    else
        pkill -f "openclaw" 2>/dev/null || true
        sleep 1
        nohup openclaw >/dev/null 2>&1 &
        disown
    fi
    echo -e " ${GREEN}✅${NC}"
    sleep 2
    return 0
}

service_status() {
    echo ""
    header "📡 OpenClaw 运行状态"
    echo "  ─────────────────────────────────"

    if $DOCKER_MODE; then
        local state uptime_str
        state=$(docker inspect "$DOCKER_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        local started
        started=$(docker inspect "$DOCKER_CONTAINER" --format '{{.State.StartedAt}}' 2>/dev/null || echo "")
        if [ -n "$started" ] && [ "$state" = "running" ]; then
            local now_epoch start_epoch diff_h
            now_epoch=$(date +%s)
            start_epoch=$(date -d "$started" +%s 2>/dev/null || echo "0")
            diff_h=$(( (now_epoch - start_epoch) / 3600 ))
            uptime_str=" (已运行 ${diff_h}h)"
        fi
        echo -e "  容器: ${DOCKER_CONTAINER}"
        echo -e "  状态: ${GREEN}${state}${NC}${uptime_str}"
        local ver
        ver=$(docker exec "$DOCKER_CONTAINER" openclaw --version 2>/dev/null || echo "")
        [ -n "$ver" ] && echo -e "  版本: ${ver}"
    elif command -v systemctl >/dev/null 2>&1; then
        local active
        active=$(systemctl is-active openclaw 2>/dev/null || echo "未知")
        echo -e "  状态: $([ "$active" = "active" ] && echo "${GREEN}运行中${NC}" || echo "${RED}${active}${NC}")"
    else
        local pid
        pid=$(pgrep -f "openclaw" 2>/dev/null | head -1 || true)
        if [ -n "$pid" ]; then
            echo -e "  PID: ${pid}  ${GREEN}运行中${NC}"
        else
            echo -e "  状态: ${RED}未运行${NC}"
        fi
    fi
    echo ""
}

service_logs() {
    echo ""
    header "📋 OpenClaw 日志（最近 50 行）"
    echo "  ─────────────────────────────────"
    echo ""

    if $DOCKER_MODE; then
        docker logs --tail=50 "$DOCKER_CONTAINER" 2>/dev/null || warn "  无法获取日志"
    elif command -v journalctl >/dev/null 2>&1; then
        journalctl -u openclaw -n 50 --no-pager 2>/dev/null || warn "  无法获取日志"
    elif [ -f "${HOME}/.openclaw/logs/agent.log" ]; then
        tail -50 "${HOME}/.openclaw/logs/agent.log"
    else
        warn "  未找到日志文件"
    fi
    echo ""
    press_any_key
}

# ============================================================
#  初始化
# ============================================================

do_init() {
    print_banner
    header "🚀 首次初始化"
    echo "  ─────────────────────────────────"
    echo ""
    echo "  即将配置 AI坤 API 作为 OpenClaw 的唯一供应商。"
    echo ""

    # 输入 API Key
    if [ -n "$API_KEY" ]; then
        local masked="${API_KEY:0:8}****"
        echo -e "  当前 Key: ${YELLOW}${masked}${NC}"
        if ! confirm_action "  是否更新 Key"; then
            :
        else
            echo -ne "  请输入新的 API Key: "
            read -r new_key
            [ -n "$new_key" ] && API_KEY="$new_key"
        fi
    else
        echo -ne "  请输入 API Key: "
        read -r new_key
        [ -n "$new_key" ] && API_KEY="$new_key"
    fi

    [ -z "$API_KEY" ] && { error "❌ API Key 不能为空"; press_any_key; return 1; }

    echo ""

    # 测试连接
    if ! test_connection "$API_KEY"; then
        error "❌ API 连接失败"
        if ! confirm_action "  是否跳过验证继续初始化"; then
            press_any_key; return 1
        fi
    fi

    echo ""

    # 拉取模型列表
    local models_raw
    models_raw=$(fetch_model_list "$API_KEY") || {
        error "❌ 拉取模型列表失败"
        press_any_key; return 1
    }

    echo ""
    header "📦 可用模型:"
    echo "  ─────────────────────────────────"

    local model_ids=()
    local i=1
    while IFS='|' read -r mid owned; do
        [ -z "$mid" ] && continue
        model_ids+=("$mid")
        echo "   ${i}) ${mid}  ${BLUE}(${owned})${NC}"
        i=$((i+1))
    done <<< "$models_raw"

    [ ${#model_ids[@]} -eq 0 ] && { error "❌ 没有获取到模型"; press_any_key; return 1; }

    echo ""
    echo -ne "  选择要启用的模型（多选用空格分隔，如 1 3 5）: "
    read -r selections

    local enabled_ids="["
    local first=true
    local first_model=""
    for sel in $selections; do
        local idx=$((sel - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#model_ids[@]} ]; then
            if $first; then
                enabled_ids+="{\"id\": \"${model_ids[$idx]}\", \"name\": \"${model_ids[$idx]}\"}"
                first_model="${model_ids[$idx]}"
                first=false
            else
                enabled_ids+=", {\"id\": \"${model_ids[$idx]}\", \"name\": \"${model_ids[$idx]}\"}"
            fi
        fi
    done
    enabled_ids+="]"

    [ -z "$first_model" ] && { error "❌ 未选择有效模型"; press_any_key; return 1; }

    local default_model="$first_model"
    # 统计选择了几个模型
    local sel_count
    sel_count=$(echo "$selections" | wc -w)
    if [ "$sel_count" -gt 1 ]; then
        echo ""
        local j=1
        for m in $selections; do
            local idx=$((m - 1))
            [ "$idx" -ge 0 ] && [ "$idx" -lt ${#model_ids[@]} ] && echo "     ${j}) ${model_ids[$idx]}" && j=$((j+1))
        done
        echo -ne "  选择默认模型（输入编号）: "
        read -r def_sel
        local di=$((def_sel - 1))
        [ "$di" -ge 0 ] && [ "$di" -lt ${#model_ids[@]} ] && default_model="${model_ids[$di]}"
    fi

    echo ""
    confirm_action "⚠️  即将写入配置，是否继续" || { press_any_key; return 1; }

    backup_config
    if write_aikun_config "$API_KEY" "$enabled_ids" "$default_model"; then
        info "✅ 配置已写入容器"
        log_msg "INFO" "初始化完成，默认模型: ${default_model}"
        save_cache
    else
        error "❌ 配置写入失败"
        press_any_key; return 1
    fi

    echo ""
    echo -ne "  ${BLUE}是否重启 OpenClaw 使配置生效？[Y/n]: "
    read -r restart_ans
    case "$restart_ans" in
        [nN]|[nN][oO]) info "  稍后手动重启即可" ;;
        *) service_restart ;;
    esac

    echo ""
    info "✅ 初始化完成！"
    press_any_key
}

# ============================================================
#  菜单函数
# ============================================================

menu_model_management() {
    while true; do
        print_banner
        header "📋 模型管理"
        echo "  ─────────────────────────────────"

        # 显示已启用的模型
        local cfg
        cfg=$(read_container_config 2>/dev/null || echo "{}")
        if [ -n "$cfg" ] && command -v python3 >/dev/null 2>&1; then
            echo "$cfg" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    primary = d.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','')
    models = d.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
    if not models:
        print('  ${YELLOW}暂无已启用的模型${NC}')
    else:
        for m in models:
            mid = m['id']
            tag = ' ${GREEN}← 默认${NC}' if f'aikun/{mid}' == primary else ''
            print(f'  ${GREEN}✅${NC} {mid}{tag}')
except: pass
" 2>/dev/null
        fi

        echo ""
        echo "  ┌──────────────────────────────────┐"
        echo "  │  1) 刷新 & 重新选择模型         │"
        echo "  │  2) 切换默认模型                │"
        echo "  │  3) 手动添加模型 ID            │"
        echo "  │  4) 禁用所有模型               │"
        echo "  │  0) 返回主菜单                 │"
        echo "  └──────────────────────────────────┘"
        echo ""
        echo -ne "  请输入选项 [0-4]: "
        read -r opt

        case "$opt" in
            1)
                [ -z "$API_KEY" ] && { error "❌ 请先配置 API Key"; press_any_key; continue; }
                local models_raw
                models_raw=$(fetch_model_list "$API_KEY") || { press_any_key; continue; }

                echo ""
                header "📦 AI坤 API 可用模型:"
                echo "  ─────────────────────────────────"
                local model_ids=(); local i=1
                while IFS='|' read -r mid owned; do
                    [ -z "$mid" ] && continue
                    model_ids+=("$mid")
                    echo "   ${i}) ${mid}  ${BLUE}(${owned})${NC}"
                    i=$((i+1))
                done <<< "$models_raw"

                echo ""
                echo -ne "  选择要启用的模型（多选用空格分隔）: "
                read -r selections

                local first=true new_ids="[" first_model=""
                for sel in $selections; do
                    local idx=$((sel - 1))
                    if [ "$idx" -ge 0 ] && [ "$idx" -lt ${#model_ids[@]} ]; then
                        $first && { new_ids+="{\"id\": \"${model_ids[$idx]}\", \"name\": \"${model_ids[$idx]}\"}"; first_model="${model_ids[$idx]}"; first=false; } || new_ids+=", {\"id\": \"${model_ids[$idx]}\", \"name\": \"${model_ids[$idx]}\"}"
                    fi
                done
                new_ids+="]"
                [ -z "$first_model" ] && { error "❌ 未选择有效模型"; press_any_key; continue; }

                backup_config
                write_aikun_config "$API_KEY" "$new_ids" "$first_model" && info "✅ 配置已更新" || error "❌ 写入失败"
                confirm_action "  是否重启 OpenClaw" && service_restart
                press_any_key
                ;;
            2)
                local cfg2
                cfg2=$(read_container_config 2>/dev/null || echo "{}")
                local model_list
                model_list=$(echo "$cfg2" | python3 -c "
import json,sys
d = json.load(sys.stdin)
models = d.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
primary = d.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','')
for i, m in enumerate(models, 1):
    tag = ' ← 当前默认' if f'aikun/{m[\"id\"]}' == primary else ''
    print(f'{i}) {m[\"id\"]}{tag}')
" 2>/dev/null) || { warn "  没有已启用的模型"; press_any_key; continue; }
                echo ""; echo "  当前已启用的模型:"; echo "$model_list"
                echo ""; echo -ne "  选择要设为默认的模型编号: "
                read -r def_sel
                local target
                target=$(echo "$cfg2" | python3 -c "
import json,sys
d = json.load(sys.stdin)
models = d.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
n = int('${def_sel}' or 0)
if 1 <= n <= len(models): print(models[n-1]['id'])
" 2>/dev/null) || true
                [ -n "$target" ] && { set_default_model "$target" && info "✅ 默认模型已切换为: ${target}"; } || error "❌ 无效选择"
                press_any_key
                ;;
            3)
                echo ""; echo -ne "  输入模型 ID (如 gpt-4o): "
                read -r manual_id
                [ -z "$manual_id" ] && { error "❌ 不能为空"; press_any_key; continue; }
                toggle_model "$manual_id" "enable" && info "✅ 已添加: ${manual_id}" || error "❌ 添加失败"
                press_any_key
                ;;
            4)
                confirm_action "⚠️  确定要禁用所有 AI坤 模型" || { press_any_key; continue; }
                local cfg4
                cfg4=$(read_container_config 2>/dev/null || echo "{}")
                local new_cfg4
                new_cfg4=$(echo "$cfg4" | python3 -c "
import json,sys
d = json.load(sys.stdin)
d.setdefault('models',{}).setdefault('providers',{}).setdefault('aikun',{})['models'] = []
d.setdefault('agents',{}).setdefault('defaults',{})['models'] = {}
d['agents']['defaults'].setdefault('model',{})['primary'] = ''
print(json.dumps(d, indent=2, ensure_ascii=False))
" 2>/dev/null) && write_container_config "$new_cfg4" && info "✅ 已禁用所有模型" || error "❌ 操作失败"
                press_any_key
                ;;
            0) return ;;
            *) warn "  无效选项"; press_any_key ;;
        esac
    done
}

menu_service() {
    while true; do
        print_banner
        header "🔧 服务管理"
        echo "  ─────────────────────────────────"
        service_status
        echo "  ┌──────────────────────────────────┐"
        echo "  │  1) 重启 OpenClaw               │"
        echo "  │  2) 启动 OpenClaw               │"
        echo "  │  3) 停止 OpenClaw               │"
        echo "  │  4) 查看日志                    │"
        echo "  │  0) 返回主菜单                  │"
        echo "  └──────────────────────────────────┘"
        echo ""
        echo -ne "  请输入选项 [0-4]: "
        read -r opt

        case "$opt" in
            1) service_restart && info "✅ OpenClaw 已重启" || error "❌ 重启失败"; press_any_key ;;
            2)
                if $DOCKER_MODE; then
                    docker start "$DOCKER_CONTAINER" 2>/dev/null && info "✅ 已启动" || error "❌ 启动失败"
                else
                    nohup openclaw >/dev/null 2>&1 &
                    info "✅ 启动命令已执行"
                fi
                press_any_key
                ;;
            3)
                if $DOCKER_MODE; then
                    docker stop "$DOCKER_CONTAINER" 2>/dev/null && info "✅ 已停止" || error "❌ 停止失败"
                else
                    pkill -f "openclaw" 2>/dev/null || true
                    info "✅ 停止命令已执行"
                fi
                press_any_key
                ;;
            4) service_logs ;;
            0) return ;;
            *) warn "  无效选项"; press_any_key ;;
        esac
    done
}

menu_config() {
    while true; do
        print_banner
        header "💾 配置与备份"
        echo "  ─────────────────────────────────"
        echo ""
        echo "  ┌──────────────────────────────────┐"
        echo "  │  1) 查看当前配置                │"
        echo "  │  2) 更新 API Key               │"
        echo "  │  3) 一键备份配置               │"
        echo "  │  4) 从备份恢复                 │"
        echo "  │  5) 查看备份列表               │"
        echo "  │  6) 更新模型参数               │"
        echo "  │  0) 返回主菜单                 │"
        echo "  └──────────────────────────────────┘"
        echo ""
        echo -ne "  请输入选项 [0-6]: "
        read -r opt

        case "$opt" in
            1)
                echo ""
                header "📋 当前配置概览"
                echo "  ─────────────────────────────────"
                local cfg
                cfg=$(read_container_config 2>/dev/null || echo "{}")
                echo "$cfg" | python3 -c "
import json,sys
d = json.load(sys.stdin)
p = d.get('models',{}).get('providers',{})
primary = d.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','未设置')
print(f'  供应商数量: {len(p)}')
print(f'  默认模型:   {primary}')
aikun = p.get('aikun',{})
if aikun:
    url = aikun.get('baseUrl','')
    key = aikun.get('apiKey','')
    models = aikun.get('models',[])
    masked = key[:8] + '****' if len(key) > 8 else '****'
    print(f'  AI坤 API: {url}')
    print(f'  API Key:  {masked}')
    print(f'  已启用模型 ({len(models)}):')
    for m in models:
        isd = '← 默认' if f'aikun/{m[\"id\"]}' == primary else ''
        print(f'    - {m[\"id\"]} {isd}')
else:
    print('  ⚠️  未配置 AI坤 供应商')
" 2>/dev/null || echo "  配置解析失败"
                echo ""
                press_any_key
                ;;
            2)
                echo ""
                header "🔑 更新 API Key"
                echo -ne "  请输入新的 API Key: "
                read -r new_key
                [ -z "$new_key" ] && { error "❌ 不能为空"; press_any_key; continue; }

                echo -ne "  ${BLUE}验证 Key..."
                local code
                code=$(docker_do curl -s -o /dev/null -w "%{http_code}" "${AIKUN_BASE}/models" -H "Authorization: Bearer ${new_key}" --connect-timeout 8 --max-time 12 2>/dev/null || echo "000")
                [ "$code" = "200" ] && echo -e " ${GREEN}✅${NC}" || { echo -e " ${RED}❌${NC}"; confirm_action "  Key 无效，仍然保存" || continue; }

                API_KEY="$new_key"
                save_cache
                # 更新容器内配置的 apiKey
                local cfg2
                cfg2=$(read_container_config 2>/dev/null || echo "{}")
                local new_cfg2
                new_cfg2=$(echo "$cfg2" | python3 -c "
import json,sys
d = json.load(sys.stdin)
d.setdefault('models',{}).setdefault('providers',{}).setdefault('aikun',{})
d['models']['providers']['aikun']['apiKey'] = '${API_KEY}'
print(json.dumps(d, indent=2, ensure_ascii=False))
" 2>/dev/null) && write_container_config "$new_cfg2" && info "✅ API Key 已更新" || warn "⚠️  写入失败"
                press_any_key
                ;;
            3) backup_config; press_any_key ;;
            4) restore_backup ;;
            5) echo ""; header "📂 备份列表:"; list_backups; echo ""; press_any_key ;;
            6)
                # 更新模型参数
                update_model_params_from_db
                press_any_key
                ;;
            0) return ;;
            *) warn "  无效选项"; press_any_key ;;
        esac
    done
}

# ============================================================
#  一键更新模型参数
# ============================================================

update_model_params_from_db() {
    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")
    
    echo ""
    header "🔄 更新模型参数"
    echo "  根据内置知识库自动填充 contextWindow / maxTokens"
    echo "  ─────────────────────────────────"

    local new_cfg
    new_cfg=$(echo "$cfg" | python3 -c "
import json,sys
cfg = json.load(sys.stdin)

MODEL_DB = {
    # ── DeepSeek ──
    'deepseek-v4-flash':    {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-v4-pro':      {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-v4':          {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-r1':          {'contextWindow': 1048576, 'maxTokens': 8192},
    'deepseek-chat':        {'contextWindow': 65536,   'maxTokens': 8192},
    'deepseek-coder':       {'contextWindow': 65536,   'maxTokens': 8192},
    'deepseek-v3':          {'contextWindow': 65536,   'maxTokens': 8192},
    # ── Kimi (月之暗面) ──
    'kimi-k2.7-code':       {'contextWindow': 1048576, 'maxTokens': 8192},
    'kimi-k2.6':            {'contextWindow': 262144,  'maxTokens': 8192},
    'kimi-k2.5':            {'contextWindow': 262144,  'maxTokens': 8192},
    # ── MiniMax ──
    'minimax-m3':           {'contextWindow': 1048576, 'maxTokens': 8192},
    'minimax-m2.5':         {'contextWindow': 1048576, 'maxTokens': 8192},
    # ── Qwen (通义千问) ──
    'qwen3.7-max':          {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen3.7-plus':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen3.6-plus':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen3.5-plus':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'qwen-max':             {'contextWindow': 32768,   'maxTokens': 8192},
    'qwen-plus':            {'contextWindow': 131072,  'maxTokens': 8192},
    'qwen-turbo':           {'contextWindow': 131072,  'maxTokens': 8192},
    'qwen-long':            {'contextWindow': 10000000, 'maxTokens': 6000},
    # ── GLM (智谱) ──
    'glm-5.2':              {'contextWindow': 131072,  'maxTokens': 8192},
    'glm-5':                {'contextWindow': 131072,  'maxTokens': 8192},
    # ── 豆包 ──
    'doubao-seed-2.0-pro':  {'contextWindow': 262144,  'maxTokens': 16384},
    'doubao-seed-2.0-code': {'contextWindow': 262144,  'maxTokens': 16384},
    # ── GPT (OpenAI) ──
    'gpt-5':                {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-5.5':              {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-5.4':              {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-5.3-codex':        {'contextWindow': 400000,  'maxTokens': 128000},
    'gpt-4o':               {'contextWindow': 128000,  'maxTokens': 16384},
    'gpt-4o-mini':          {'contextWindow': 128000,  'maxTokens': 16384},
    'gpt-4-turbo':          {'contextWindow': 128000,  'maxTokens': 4096},
    'gpt-4':                {'contextWindow': 8192,    'maxTokens': 8192},
    'gpt-3.5-turbo':        {'contextWindow': 16385,   'maxTokens': 4096},
    'o1':                   {'contextWindow': 200000,  'maxTokens': 100000},
    'o1-mini':              {'contextWindow': 128000,  'maxTokens': 65536},
    'o1-preview':           {'contextWindow': 128000,  'maxTokens': 32768},
    'o3-mini':              {'contextWindow': 200000,  'maxTokens': 100000},
    # ── Claude (Anthropic) ──
    'claude-opus-4.8':      {'contextWindow': 1048576, 'maxTokens': 131072},
    'claude-sonnet-4.6':    {'contextWindow': 1048576, 'maxTokens': 131072},
    'claude-opus-4.1':      {'contextWindow': 200000,  'maxTokens': 32768},
    'claude-3.5-sonnet':    {'contextWindow': 200000,  'maxTokens': 8192},
    'claude-3.5-haiku':     {'contextWindow': 200000,  'maxTokens': 8192},
    'claude-3-opus':        {'contextWindow': 200000,  'maxTokens': 4096},
    'claude-3-sonnet':      {'contextWindow': 200000,  'maxTokens': 4096},
    'claude-3-haiku':       {'contextWindow': 200000,  'maxTokens': 4096},
    # ── Gemini (Google) ──
    'gemini-3-pro':         {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-3.1-pro':       {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-3.5-flash':     {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-2.5-pro':       {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-2.5-flash':     {'contextWindow': 1048576, 'maxTokens': 65536},
    'gemini-2.0-flash':     {'contextWindow': 1048576, 'maxTokens': 8192},
    'gemini-1.5-pro':       {'contextWindow': 2000000, 'maxTokens': 8192},
    'gemini-1.5-flash':     {'contextWindow': 1048576, 'maxTokens': 8192},
    # ── Llama (Meta) ──
    'llama-4-maverick':     {'contextWindow': 1048576, 'maxTokens': 8192},
    'llama-4-scout':        {'contextWindow': 10000000, 'maxTokens': 8192},
    # ── Grok (xAI) ──
    'grok-4.1':             {'contextWindow': 1048576, 'maxTokens': 32768},
}

models = cfg.get('models',{}).get('providers',{}).get('aikun',{}).get('models',[])
if not models:
    print('ERROR')
    sys.exit(0)

def fetch_model_params(mid):
    import urllib.request, urllib.error
    provider_map = {
        'gpt': 'openai', 'o1': 'openai', 'o3': 'openai',
        'claude': 'anthropic',
        'gemini': 'google-gemini',
        'grok': 'xai',
        'mistral': 'mistral', 'mixtral': 'mistral',
    }
    prefix = mid.split('-')[0].split('.')[0].lower()
    provider = provider_map.get(prefix)
    if not provider:
        return None
    filename = mid.replace('.', '-')
    url = f'https://raw.githubusercontent.com/truefoundry/models/main/providers/{provider}/{filename}.yaml'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'aikun-manager/1.0'})
        with urllib.request.urlopen(req, timeout=5) as r:
            content = r.read().decode()
            ctx = out = None
            for line in content.split('\n'):
                line = line.strip()
                if line.startswith('context_window:'):
                    ctx = int(line.split(':')[1].strip())
                elif line.startswith('max_output_tokens:'):
                    out = int(line.split(':')[1].strip())
            if ctx:
                return {'contextWindow': ctx, 'maxTokens': out or 4096}
    except:
        pass
    return None

updated = 0
for m in models:
    mid = m.get('id','')
    remote = fetch_model_params(mid)
    db = remote if remote else MODEL_DB.get(mid, {})
    if db:
        old_cw = m.get('contextWindow', '?')
        old_mt = m.get('maxTokens', '?')
        new_cw = db.get('contextWindow')
        new_mt = db.get('maxTokens')
        m['contextWindow'] = new_cw
        m['maxTokens'] = new_mt
        updated += 1
        print(f'  ✅ {mid}: ctx {old_cw} -> {new_cw}  out {old_mt} -> {new_mt}')
    else:
        if 'contextWindow' not in m:
            m['contextWindow'] = 128000
        if 'maxTokens' not in m:
            m['maxTokens'] = 4096
        print(f'  ⚠️  {mid}: 未找到知识库记录，使用默认')

if updated > 0:
    print(f'RESULT:{updated}')
    print(json.dumps(cfg, indent=2, ensure_ascii=False))
else:
    print('RESULT:0')
" 2>/dev/null) || { error "❌ 执行失败"; return 1; }

    # 解析结果
    local result_line
    result_line=$(echo "$new_cfg" | grep '^RESULT:' | head -1)
    local count=${result_line#RESULT:}
    
    if [ "$count" = "ERROR" ]; then
        warn "  暂无已启用的模型"
        return 1
    fi

    if [ "$count" -gt 0 ] 2>/dev/null; then
        local json_part
        json_part=$(echo "$new_cfg" | sed '/^RESULT:/d' | sed '/^  ✅/d' | sed '/^  ⚠️/d')
        echo ""
        confirm_action "  确认写入配置？" || return 0
        write_container_config "$json_part" && info "✅ 已更新 ${count} 个模型的参数" || error "❌ 写入失败"
    else
        info "  所有模型参数已是最新"
    fi
    return 0
}

menu_diagnose() {
    print_banner
    header "🩺 环境诊断"
    echo "  ─────────────────────────────────"
    echo ""

    local issues=0

    # 1. 依赖检查
    echo -ne "  ${BLUE}curl...${NC}"
    command -v curl >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || { echo -e " ${RED}❌${NC}"; issues=$((issues+1)); }

    echo -ne "  ${BLUE}python3...${NC}"
    command -v python3 >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || { echo -e " ${YELLOW}⚠️  建议安装${NC}"; }

    echo -ne "  ${BLUE}jq...${NC}"
    command -v jq >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || { echo -e " ${YELLOW}❌ (可选)${NC}"; }

    echo ""

    # 2. Docker 检测
    local docker_ok=false
    if command -v docker >/dev/null 2>&1; then
        echo -e "  ${BLUE}Docker...${NC} ${GREEN}✅${NC}"
        docker_ok=true
    else
        echo -e "  ${BLUE}Docker...${NC} ${RED}❌${NC}"
        issues=$((issues+1))
    fi

    # 3. OpenClaw 容器
    local container_running=false container_existed=false container_name=""
    if $docker_ok; then
        local running existed
        running=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i openclaw | head -1 || true)
        existed=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -i openclaw | head -1 || true)

        if [ -n "$running" ]; then
            container_running=true; container_name="$running"
            echo -e "  OpenClaw: ${GREEN}Docker 运行中${NC} ($container_name)"
        elif [ -n "$existed" ]; then
            container_existed=true; container_name="$existed"
            echo -e "  OpenClaw: ${YELLOW}容器已停止${NC} ($existed)"
            issues=$((issues+1))
        else
            echo -e "  OpenClaw: ${RED}未安装${NC}"
            issues=$((issues+1))
        fi
    fi

    echo ""

    # 4. 端口连通性
    local port_open=false
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:18790/ 2>/dev/null || echo "000")
    if [ "$code" != "000" ]; then
        echo -e "  ${BLUE}本地网关 (18790)...${NC} ${GREEN}可达 (HTTP ${code})${NC}"
        port_open=true
    else
        echo -e "  ${BLUE}本地网关 (18790)...${NC} ${RED}不可达${NC}"
        issues=$((issues+1))
    fi

    echo ""

    # 5. AI坤 API
    if [ -n "$API_KEY" ]; then
        echo -ne "  ${BLUE}AI坤 API 连通性...${NC}"
        local code2
        code2=$(curl -s -o /dev/null -w "%{http_code}" "${AIKUN_BASE}/models" \
            -H "Authorization: Bearer ${API_KEY}" --connect-timeout 8 --max-time 12 2>/dev/null || echo "000")
        [ "$code2" = "200" ] && echo -e " ${GREEN}✅${NC}" || echo -e " ${YELLOW}⚠️ (HTTP ${code2})${NC}"
    else
        echo -e "  AI坤 API: ${YELLOW}未配置 Key${NC}"
    fi

    echo ""
    echo "  ─────────────────────────────────"
    echo ""

    # 6. 诊断结果 + 修复
    local has_fix=false
    
    if [ "$issues" -eq 0 ]; then
        info "  ✅ 一切正常，无需修复"
    else
        warn "  ⚠️  发现 ${issues} 个问题"
        echo ""
        local fix_count=0

        if ! $container_existed && ! $container_running && $docker_ok; then
            fix_count=$((fix_count+1))
            echo "  ${fix_count}) 📦 安装 OpenClaw"
            has_fix=true
        fi
        
        if $container_existed && ! $container_running; then
            fix_count=$((fix_count+1))
            echo "  ${fix_count}) 🔧 启动 OpenClaw 容器"
            has_fix=true
        fi

        if [ "$fix_count" -gt 0 ]; then
            echo "  0) 返回主菜单"
            echo ""
            echo -ne "  请选择修复项 [0-${fix_count}]: "
            read -r fix_opt

            local cur=0
            if [ "$fix_opt" != "0" ] && [ -n "$fix_opt" ]; then
                # 安装 OpenClaw
                if ! $container_existed && ! $container_running && $docker_ok; then
                    cur=$((cur+1))
                    [ "$fix_opt" = "$cur" ] && {
                        echo ""
                        header "📦 选择 OpenClaw 版本"
                        echo "  ─────────────────────────────────"
                        echo ""
                        echo "  1) 官方版 (openclaw/openclaw:latest)"
                        echo "  2) 汉化版 (1186258278/openclaw-zh:latest)"
                        echo ""
                        echo -ne "  请选择 [1-2]: "
                        read -r ver_opt
                        
                        local image=""
                        case "$ver_opt" in
                            1) image="openclaw/openclaw:latest" ;;
                            2) image="1186258278/openclaw-zh:latest" ;;
                            *) image="openclaw/openclaw:latest" ;;
                        esac

                        echo ""
                        echo -ne "  ${BLUE}拉取镜像 ${image}...${NC}"
                        docker pull "$image" >/dev/null 2>&1 && echo -e " ${GREEN}✅${NC}" || {
                            echo -e " ${RED}❌${NC}"
                            error "  拉取失败，请检查网络"
                            press_any_key; continue 2>/dev/null || true
                            return
                        }

                        echo -ne "  ${BLUE}创建并启动容器...${NC}"
                        local gw_cmd="gateway --port 18790"
                        [ "$ver_opt" = "2" ] && gw_cmd="openclaw gateway run"
                        
                        docker rm -f openclaw 2>/dev/null || true
                        if docker run -d \
                            --name openclaw \
                            --restart unless-stopped \
                            -p 18790:18790 \
                            "$image" \
                            $gw_cmd >/dev/null 2>&1; then
                            echo -e " ${GREEN}✅${NC}"
                            info "  OpenClaw 已安装并启动"
                            sleep 3
                            local c
                            c=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost:18790/ 2>/dev/null || echo "000")
                            [ "$c" != "000" ] && info "  服务已就绪" || warn "  服务尚未完全响应，请稍后检查"
                            # 自动设为 Docker 模式
                            DOCKER_MODE=true; DOCKER_CONTAINER="openclaw"
                        else
                            echo -e " ${RED}❌${NC}"
                            error "  启动失败"
                        fi
                    }
                fi
                
                # 启动已停止的容器
                if $container_existed && ! $container_running; then
                    cur=$((cur+1))
                    [ "$fix_opt" = "$cur" ] && {
                        echo -ne "  ${BLUE}启动容器...${NC}"
                        docker start "$container_name" >/dev/null 2>&1 && {
                            DOCKER_MODE=true; DOCKER_CONTAINER="$container_name"
                            echo -e " ${GREEN}✅${NC}"
                            sleep 3
                            local c
                            c=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost:18790/ 2>/dev/null || echo "000")
                            [ "$c" != "000" ] && info "  OpenClaw 已就绪" || warn "  服务尚未响应"
                        } || echo -e " ${RED}❌${NC}"
                    }
                fi
            fi
        fi
    fi

    if ! $has_fix && [ "$issues" -gt 0 ]; then
        warn "  暂无可用自动修复"
    fi

    echo ""
    press_any_key
}

menu_webpage() {
    local gw_port="18790" gw_token=""

    # 从 Docker 环境变量读取 token
    if $DOCKER_MODE && [ -n "$DOCKER_CONTAINER" ]; then
        local docker_token
        docker_token=$(docker inspect "$DOCKER_CONTAINER" 2>/dev/null | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    env = d[0].get('Config',{}).get('Env',[])
    for e in env:
        if 'OPENCLAW_GATEWAY_TOKEN' in e:
            print(e.split('=',1)[1]); break
except: pass
" 2>/dev/null || echo "")
        [ -n "$docker_token" ] && gw_token="$docker_token"
    fi

    # 从配置文件兜底
    if [ -z "$gw_token" ]; then
        local cfg
        cfg=$(read_container_config 2>/dev/null || echo "{}")
        local info
        info=$(echo "$cfg" | python3 -c "
import json,sys
d = json.load(sys.stdin)
port = d.get('gateway',{}).get('port', 18790)
tok = d.get('gateway',{}).get('auth',{}).get('token','')
print(f'{port}|{tok}')
" 2>/dev/null || echo "18790|")
        gw_port="${info%%|*}"
        [ -z "$gw_token" ] && gw_token="${info#*|}"
    fi

    local api_url="http://localhost:${gw_port}"
    local web_url="http://localhost:${gw_port}"
    [ -n "$gw_token" ] && web_url="http://localhost:${gw_port}/?token=${gw_token}"

    echo ""
    header "📖 OpenClaw 使用信息"
    echo "  ─────────────────────────────────"
    echo ""
    echo -e "  ${BOLD}🔗 API 地址（程序调用）：${NC}"
    echo -e "  ${CYAN}${api_url}${NC}"
    echo ""
    echo -e "  ${BOLD}🌐 管理界面（浏览器打开）：${NC}"
    echo -e "  ${CYAN}${web_url}${NC}"
    echo ""
    [ -n "$gw_token" ] && {
        local masked="${gw_token:0:6}****"
        echo -e "  ${BOLD}🔑 访问令牌（Token）：${NC}${YELLOW}${masked}${NC}"
        echo ""
        echo -e "  ${BOLD}📝 调用示例（curl）：${NC}"
        echo "  curl ${api_url}/v1/chat/completions \\"
        echo "    -H \"Authorization: Bearer ${gw_token}\" \\"
        echo "    -H \"Content-Type: application/json\" \\"
        echo "    -d '{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}'"
    }
    echo ""
    echo -e "  ${BOLD}⚙️  运行方式：${NC}${GREEN}Docker${NC}"
    $DOCKER_MODE && echo "  容器: ${DOCKER_CONTAINER}"
    echo ""
    echo "  ─────────────────────────────────"
    echo ""
    press_any_key
}

# ============================================================
#  主菜单
# ============================================================

main_menu() {
    while true; do
        print_banner
        print_status_bar
        echo ""
        echo "  ┌──────────────────────────────────┐"
        echo "  │  1) 📋 模型管理                  │"
        echo "  │  2) 🔧 服务管理                  │"
        echo "  │  3) 💾 配置与备份                │"
        echo "  │  4) 🩺 环境诊断                  │"
        echo "  │  5) 📖 查看使用网址              │"
        echo "  │                                  │"
        echo "  │  0) ❌ 退出                      │"
        echo "  └──────────────────────────────────┘"
        echo ""
        echo -ne "  请输入选项 [0-5]: "
        read -r opt

        case "$opt" in
            1) menu_model_management ;;
            2) menu_service ;;
            3) menu_config ;;
            4) menu_diagnose ;;
            5) menu_webpage ;;
            0) cleanup_and_exit ;;
            *) warn "  无效选项，请重试" ; sleep 1 ;;
        esac
    done
}

# ============================================================
#  入口
# ============================================================

main() {
    # 安装模式
    if [ "${1:-}" = "--install" ] || [ "${1:-}" = "-i" ]; then
        do_install
        exit 0
    fi

    # 检测 Docker 模式
    detect_openclaw_mode || true

    # 读取 API Key
    read_api_key

    # 未配置则进入初始化
    local configured=false
    local cfg
    cfg=$(read_container_config 2>/dev/null || echo "{}")
    if [ -n "$cfg" ] && command -v python3 >/dev/null 2>&1; then
        local has_key
        has_key=$(echo "$cfg" | python3 -c "
import json,sys
d = json.load(sys.stdin)
k = d.get('models',{}).get('providers',{}).get('aikun',{}).get('apiKey','')
print('YES' if k else 'NO')
" 2>/dev/null || echo "NO")
        [ "$has_key" = "YES" ] && configured=true
    fi

    if ! $configured; then
        echo ""
        warn "⚠️  未检测到 AI坤 配置"
        if confirm_action "  是否进入初始化引导"; then
            do_init
        fi
    fi

    # 进主菜单
    main_menu
}

main "$@"
