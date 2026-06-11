#!/usr/bin/env bash
# ============================================================================
# CyberStrikeAI 工具一键安装脚本
# ----------------------------------------------------------------------------
# 解决问题: 工具执行失败: exec: "xxx": executable file not found in $PATH
#           跑 skill 时不同工具缺失导致任务无法继续 (issue #139)
#
# 工作方式:
#   1. 自动扫描 tools/*.yaml 中声明的所有工具 (name + command)
#   2. 在 Kali / Debian / Ubuntu / Parrot 上优先使用 apt 安装
#   3. apt 找不到的, 依次降级到 pip / gem / go install / GitHub release
#   4. 已安装的自动跳过, 不会重复执行
#
# 用法:
#   ./install-tools.sh                    # 安装所有工具
#   ./install-tools.sh --check            # 只检查, 不安装
#   ./install-tools.sh --list             # 列出所有工具及状态
#   ./install-tools.sh --only nmap,gau    # 只安装指定工具
#   ./install-tools.sh --skip msfvenom    # 跳过指定工具
#   ./install-tools.sh --dry-run          # 模拟运行
#   ./install-tools.sh --method apt       # 强制使用某种安装方式
#   ./install-tools.sh --no-sudo          # 不使用 sudo (用于已是 root 的环境)
#   ./install-tools.sh --verbose          # 显示安装命令输出 (排错用)
#   ./install-tools.sh --install-bash     # macOS: 用 Homebrew 安装 bash 4+ 并继续
#
# 环境变量 (可选):
#   PIP_INDEX_URL   自定义 pip 镜像源 (未设置时: 中文环境用清华源, 其他用 pypi.org)
#   GOPROXY         自定义 Go 模块代理 (未设置时: 中文环境用 goproxy.cn)
#   INSTALL_PREFIX  自定义二进制安装目录 (默认 /usr/local/bin)
#   VERBOSE         设为 1 等同 --verbose
#
# 平台说明:
#   主力支持 Kali / Debian / Ubuntu (apt). macOS 仅 pip/go/GitHub 部分可用.
# ============================================================================

# bash 4+ 必需 (关联数组). macOS 自带 3.2 — 自动寻找 Homebrew bash 或 --install-bash
__csai_find_bash4() {
    local c prefix
    for c in \
        "${BASH4:-}" \
        /opt/homebrew/bin/bash \
        /usr/local/opt/bash/bin/bash \
        /usr/local/bin/bash; do
        [[ -z "$c" || ! -x "$c" ]] && continue
        if "$c" -c '((BASH_VERSINFO[0] >= 4))' 2>/dev/null; then
            echo "$c"
            return 0
        fi
    done
    if command -v brew >/dev/null 2>&1; then
        prefix="$(brew --prefix bash 2>/dev/null)" || true
        c="${prefix}/bin/bash"
        if [[ -n "$prefix" && -x "$c" ]] && "$c" -c '((BASH_VERSINFO[0] >= 4))' 2>/dev/null; then
            echo "$c"
            return 0
        fi
    fi
    return 1
}

__csai_reexec_bash4() {
    local b4
    b4="$(__csai_find_bash4)"
    [[ -n "$b4" ]] || return 1
    exec "$b4" "$0" "$@"
}

if ((BASH_VERSINFO[0] < 4)); then
    want_install_bash=0
    for arg in "$@"; do
        [[ "$arg" == "--install-bash" ]] && want_install_bash=1
    done
    if [[ $want_install_bash -eq 1 ]]; then
        if ! command -v brew >/dev/null 2>&1; then
            echo "[-] --install-bash 需要 Homebrew: https://brew.sh" >&2
            exit 1
        fi
        echo "[*] 通过 Homebrew 安装 bash 4+ ..."
        brew install bash
        __csai_reexec_bash4 "$@" || true
    fi
    if ! __csai_reexec_bash4 "$@"; then
        echo "[!] 此脚本需要 bash 4.0+, 当前是: $BASH_VERSION" >&2
        if command -v brew >/dev/null 2>&1; then
            echo "    macOS 一键修复:  ./install-tools.sh --install-bash --list" >&2
            echo "    或手动: brew install bash" >&2
        else
            echo "    macOS: 安装 Homebrew 后运行  ./install-tools.sh --install-bash" >&2
        fi
        echo "    Kali/Debian/Ubuntu: 默认 bash 5.x, 直接运行即可" >&2
        exit 1
    fi
fi

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$ROOT_DIR/tools"

# ----------------------------------------------------------------------------
# 颜色与日志
# ----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

info()    { echo -e "${BLUE}[i]${NC} $*"; }
success() { echo -e "${GREEN}[+]${NC} $*"; }
warning() { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[-]${NC} $*"; }
note()    { echo -e "${CYAN}[*]${NC} $*"; }
dim()     { echo -e "${GRAY}    $*${NC}"; }

VERBOSE="${VERBOSE:-0}"
log_run() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# ----------------------------------------------------------------------------
# 默认源 (按语言环境选择镜像, 可被环境变量覆盖)
# ----------------------------------------------------------------------------
is_zh_locale() {
    [[ "${LANG:-}${LC_ALL:-}" == *zh_* ]]
}

if [[ -z "${PIP_INDEX_URL:-}" ]]; then
    if is_zh_locale; then
        PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
    else
        PIP_INDEX_URL="https://pypi.org/simple"
    fi
fi
if [[ -z "${GOPROXY:-}" ]]; then
    if is_zh_locale; then
        GOPROXY="https://goproxy.cn,direct"
    else
        GOPROXY="https://proxy.golang.org,direct"
    fi
fi
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/bin}"

# 状态统计
declare -A STATUS=()    # name -> ok|skip|fail|manual
declare -A METHOD=()    # name -> method used
declare -A SKIP_REASON=()
TOTAL=0
OK_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0
MANUAL_COUNT=0

# ----------------------------------------------------------------------------
# 参数解析
# ----------------------------------------------------------------------------
MODE="install"          # install | check | list | dry-run
ONLY_TOOLS=""
SKIP_TOOLS=""
FORCE_METHOD=""
USE_SUDO="auto"

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)    MODE="check"; shift ;;
        --list)     MODE="list"; shift ;;
        --dry-run)  MODE="dry-run"; shift ;;
        --only)     ONLY_TOOLS="${2:-}"; shift 2 ;;
        --skip)     SKIP_TOOLS="${2:-}"; shift 2 ;;
        --method)   FORCE_METHOD="${2:-}"; shift 2 ;;
        --no-sudo)  USE_SUDO="no"; shift ;;
        --sudo)     USE_SUDO="yes"; shift ;;
        --verbose|-v) VERBOSE=1; shift ;;
        --install-bash) shift ;;  # 已在启动阶段处理
        -h|--help)  usage ;;
        *)          error "未知参数: $1"; usage ;;
    esac
done

# ----------------------------------------------------------------------------
# 系统检测
# ----------------------------------------------------------------------------
DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_FAMILY=""     # debian | macos | other
PKG_MGR=""           # apt | brew | unknown
SUDO_CMD=""

detect_distro() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        DISTRO_FAMILY="macos"
        PKG_MGR="brew"
        DISTRO_ID="macos"
        return
    fi

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
    elif [[ -f /etc/lsb-release ]]; then
        # shellcheck disable=SC1091
        . /etc/lsb-release
        DISTRO_ID="${DISTRIB_ID:-unknown}"
    else
        DISTRO_ID="unknown"
    fi

    case "$DISTRO_ID" in
        kali)              DISTRO_FAMILY="debian" ;;
        parrot*|debian|ubuntu|linuxmint|elementary|pop|deepin)
                           DISTRO_FAMILY="debian" ;;
        centos|rhel|fedora|rocky|alma|amazon)
                           DISTRO_FAMILY="rhel" ;;
        arch|manjaro|endeavouros)
                           DISTRO_FAMILY="arch" ;;
        *)
            if [[ "$DISTRO_LIKE" == *debian* ]]; then
                DISTRO_FAMILY="debian"
            elif [[ "$DISTRO_LIKE" == *rhel* ]]; then
                DISTRO_FAMILY="rhel"
            else
                DISTRO_FAMILY="other"
            fi
            ;;
    esac

    case "$DISTRO_FAMILY" in
        debian) PKG_MGR="apt" ;;
        rhel)   PKG_MGR="dnf" ;;
        arch)   PKG_MGR="pacman" ;;
    esac
}

setup_sudo() {
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
        return
    fi
    case "$USE_SUDO" in
        yes) SUDO_CMD="sudo" ;;
        no)
            if [[ $EUID -ne 0 ]]; then
                error "需要 root 权限才能继续, 但 --no-sudo 已指定"
                error "请以 root 身份运行, 或去掉 --no-sudo"
                exit 1
            fi
            SUDO_CMD=""
            ;;
        auto)
            if command -v sudo >/dev/null 2>&1; then
                SUDO_CMD="sudo"
            else
                if [[ $EUID -ne 0 ]]; then
                    error "需要 root 权限, 但系统未安装 sudo"
                    exit 1
                fi
                SUDO_CMD=""
            fi
            ;;
    esac
}

# ----------------------------------------------------------------------------
# 工具映射表
# ----------------------------------------------------------------------------
# 字段: name|cmd|apt|pip|gem|go|github_repo|binary_url|note
#   - name:        tools/*.yaml 中的 name
#   - cmd:         实际可执行文件名 (用于 command -v 检测)
#   - apt:         Debian/Kali 包名 (空表示跳过)
#   - pip:         PyPI 包名 (空表示跳过)
#   - gem:         Ruby gem 包名
#   - go:          go install 路径 (github.com/xxx/cmd@latest)
#   - github_repo: GitHub 仓库 owner/repo 用于下载 release (格式 owner/repo)
#   - binary_url:  自定义二进制直链
#   - note:        备注
#
# 优先级: apt > brew(自动) > pip(映射+PyPI自动探测) > gem > go > github release
#   非 apt 平台: 按 apt/name/cmd 依次尝试 Homebrew; 再按 pip列/name/cmd/apt 探测 PyPI
# ----------------------------------------------------------------------------
get_tool_map() {
    cat <<'EOF'
amass|amass|amass|||||Kali 自带
angr|python3||angr|||||二进制较重, 首次编译耗时长
api-schema-analyzer|spectral|||||||需要 Node.js (npm install)
arjun|arjun|arjun|arjun||||Kali 自带
arp-scan|arp-scan|arp-scan|||||Kali 自带
binwalk|binwalk|binwalk|||||Kali 自带
bloodhound|bloodhound-python||bloodhound|||或 apt:bloodhound
checkov|checkov||checkov||||需 pip
checksec|checksec|checksec|||||Kali 自带
clair|clair|||||quay/clair|需 Docker 或单独下载二进制
cloudmapper|cloudmapper||cloudmapper||||
dalfox|dalfox|dalfox|||github.com/hahwul/dalfox/v2||
dirsearch|dirsearch|dirsearch|dirsearch||||
dnsenum|dnsenum|dnsenum|||||Kali 自带
dnslog|python3||||||||内部 Python 包装, 无需单独安装
dotdotpwn|dotdotpwn|dotdotpwn|||||Kali 自带
enum4linux-ng|enum4linux-ng|enum4linux-ng|||||Kali 自带
exec|sh||||||||内置 sh, 跳过
execute-python-script|/bin/bash||||||||内置 bash, 跳过
exiftool|exiftool|libimage-exiftool-perl||||apt 包名: libimage-exiftool-perl
falco|falco|falco|||||Kali 自带
feroxbuster|feroxbuster|feroxbuster|||github.com/epi052/feroxbuster|可能需 GitHub release
ffuf|ffuf|ffuf|||||Kali 自带
fierce|fierce|fierce|fierce||||
fofa_search|python3||requests||||fofa-py (需 API key)
foremost|foremost|foremost|||||Kali 自带
fscan|fscan|||||shelldigger/fscan|国内开源, GitHub release
gau|gau|gau|||github.com/lc/gau||
gdb|gdb|gdb|||||Kali 自带
ghidra|analyzeHeadless|ghidra|||||包较大, 可能需手动确认
gobuster|gobuster|gobuster|||||Kali 自带
graphql-scanner|graphqlmap||graphqlmap|||||或 git clone
hashcat|hashcat|hashcat|||||Kali 自带
hashpump|hashpump|hashpump|||||Kali 自带
http-framework-test|python3||requests||||内置 Python 包装
hydra|hydra|hydra|||||Kali 自带
impacket|python3|python3-impacket|impacket||||优先 apt
install-python-package|/bin/bash||||||||内置, 跳过
jaeles|jaeles|jaeles|||github.com/jaeles-project/jaeles||
john|john|john|||||Kali 自带
jwt-analyzer|jwt_tool|jwt|jwt-tool|||apt 包 jwt 提供 jwt_tool
katana|katana|katana|||github.com/projectdiscovery/katana/v2||
kube-bench|kube-bench|kube-bench|||||Kali 自带
kube-hunter|kube-hunter||kube-hunter|||pip 安装
libc-database|python3|libc-database||||niklasb/libc-database||git clone 较慢
lightx|lightx|||||zyylhn/lightx|需 GitHub release
linpeas|linpeas.sh||||||从 GitHub 下载脚本到 /usr/local/bin
masscan|masscan|masscan|||||Kali 自带
metasploit|python3|metasploit-framework|||||依赖 msfconsole
msfvenom|msfvenom|metasploit-framework|||||由 metasploit-framework 提供
nbtscan|nbtscan|nbtscan|||||Kali 自带
netexec|netexec|netexec|netexec||||
nikto|nikto|nikto|||||Kali 自带
nmap|nmap|nmap|||||Kali 自带
nuclei|nuclei|nuclei|||github.com/projectdiscovery/nuclei/v3/cmd/nuclei||
objdump|objdump|binutils|||||由 binutils 提供
one-gadget|one_gadget|one-gadget|one_gadget|||apt one-gadget
pacu|pacu||pacu||||
paramspider|paramspider||paramspider||||
prowler|prowler||prowler||||
pwninit|pwninit|pwninit|||github.com/io12/pwninit||
pwntools|python3||pwntools|||较重
quake_search|python3||requests||||quake 需 API key
query_execution_result|internal:query_execution_result||||||||内置, 跳过
radare2|r2|radare2|||||apt 包 radare2 提供 r2
responder|python3|responder||||Kali 自带 responder
ropgadget|ROPgadget||ROPgadget|||pip 安装
ropper|ropper|ropper|ropper|||Kali 自带
rpcclient|python3|samba-common-bin||||samba-common-bin 提供 rpcclient
rustscan|rustscan|rustscan|||github.com/RustScan/RustScan||
scout-suite|scout||scoutsuite||||
shodan_search|python3||shodan|||需 API key
smbmap|smbmap|smbmap|||||Kali 自带
sqlmap|sqlmap|sqlmap|||||Kali 自带
steghide|steghide|steghide|||||Kali 自带
strings|strings|binutils|||||由 binutils 提供
subfinder|subfinder|subfinder|||github.com/projectdiscovery/subfinder/v2/cmd/subfinder||
terrascan|terrascan|terrascan|||||Kali 自带
trivy|trivy|trivy|||||Kali 自带
volatility3|volatility3|volatility3|volatility3|||Kali 自带
wafw00f|wafw00f|wafw00f|||||Kali 自带
waybackurls|waybackurls|waybackurls|||github.com/tomnomnom/waybackurls||
wpscan|wpscan|wpscan|||||Kali 自带
x8|x8|x8|||github.com/Sh1Yo/x8||
xsser|xsser|xsser|||||Kali 自带
xxd|xxd|vim-gtk3|xxd||||Kali 装 vim 即可
zap|zap-cli||zapcli|||pip 安装
zoomeye_search|python3||zoomeye-sdk|||zoomeye 需 API key
zsteg|zsteg|zsteg|zsteg|||apt:ruby-zsteg
EOF
}

# 把映射加载到数组 (容忍列数不齐, 自动纠正常见错位)
declare -A M=()
load_map() {
    local line name rest cmd apt pip gem go gh bin_url note
    local nfields
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        name="${line%%|*}"
        rest="${line#*|}"
        # 补齐 cmd..note 共 8 段 (bash 3.2 不用 local -a)
        nfields=$(awk -F'|' '{print NF}' <<< "$rest")
        while (( nfields < 8 )); do
            rest="${rest}|"
            nfields=$((nfields + 1))
        done
        IFS='|' read -r cmd apt pip gem go gh bin_url note <<< "$rest"

        # gem 列误填 GitHub owner/repo → 提升到 gh
        if [[ "$gem" == */* && -z "$go" && -z "$gh" ]]; then
            gh="$gem"
            gem=""
        fi
        # gh 列误填备注 (无 /) → 移到 note
        if [[ -n "$gh" && "$gh" != */* && -z "$bin_url" && -z "$note" ]]; then
            note="$gh"
            gh=""
        fi
        # bin_url 列误填备注 → 移到 note
        if [[ -n "$bin_url" && -z "$note" && "$bin_url" != http* ]]; then
            note="$bin_url"
            bin_url=""
        fi

        M["$name|cmd"]="$cmd"
        M["$name|apt"]="$apt"
        M["$name|pip"]="$pip"
        M["$name|gem"]="$gem"
        M["$name|go"]="$go"
        M["$name|gh"]="$gh"
        M["$name|bin"]="$bin_url"
        M["$name|note"]="$note"
    done < <(get_tool_map)
}

# 从 tools/*.yaml 抽取 name 与 command
declare -A YAML_CMD=()
declare -A YAML_ENABLED=()
discover_tools() {
    local f name cmd enabled
    for f in "$TOOLS_DIR"/*.yaml "$TOOLS_DIR"/*.yml; do
        [[ -f "$f" ]] || continue
        name=$(grep -E "^name:" "$f" | head -1 | sed -E 's/^name:[[:space:]]*"?([^"]+)"?.*/\1/')
        cmd=$(grep -E "^command:" "$f" | head -1 | sed -E 's/^command:[[:space:]]*"?([^"]+)"?.*/\1/')
        enabled=$(grep -E "^enabled:" "$f" | head -1 | sed -E 's/^enabled:[[:space:]]*"?([^"]+)"?.*/\1/')
        if [[ -n "$name" ]]; then
            YAML_CMD["$name"]="$cmd"
            YAML_ENABLED["$name"]="${enabled:-true}"
        fi
    done
}

validate_tool_coverage() {
    local name
    for name in "${!YAML_CMD[@]}"; do
        if [[ -z "${M[$name|cmd]:-}" ]]; then
            warning "tools/${name}.yaml 未纳入 install-tools 映射表, 将不会自动安装"
        fi
    done
}

# ----------------------------------------------------------------------------
# 检测工具是否已安装 (按工具名判断, 避免 python3 包装器误报)
# ----------------------------------------------------------------------------
resolve_cmd() {
    local name="$1"
    echo "${M[$name|cmd]:-${YAML_CMD[$name]:-$name}}"
}

cmd_on_path() {
    local cmd="$1"
    [[ -n "$cmd" ]] && command -v "$cmd" >/dev/null 2>&1
}

is_builtin_tool() {
    case "$1" in
        exec|execute-python-script|install-python-package|query_execution_result|dnslog|http-framework-test)
            return 0 ;;
    esac
    return 1
}

is_installed() {
    local name="$1"
    local cmd="${2:-$(resolve_cmd "$name")}"

    case "$name" in
        angr)           python3 -c "import angr"     >/dev/null 2>&1 && return 0 ;;
        pwntools)       python3 -c "import pwn"       >/dev/null 2>&1 && return 0 ;;
        impacket)       python3 -c "import impacket"  >/dev/null 2>&1 && return 0 ;;
        metasploit)     cmd_on_path msfconsole && return 0 ;;
        msfvenom)       cmd_on_path msfvenom && return 0 ;;
        responder)      cmd_on_path responder && return 0 ;;
        rpcclient)      cmd_on_path rpcclient && return 0 ;;
        bloodhound)     cmd_on_path bloodhound-python && return 0 ;;
        shodan_search)  python3 -c "import shodan"    >/dev/null 2>&1 && return 0 ;;
        zoomeye_search) python3 -c "import zoomeye"   >/dev/null 2>&1 && return 0 ;;
        fofa_search|quake_search)
            python3 -c "import requests" >/dev/null 2>&1 && return 0 ;;
        libc-database)
            [[ -d /usr/share/libc-database || -d "$HOME/libc-database" ]] && return 0 ;;
        api-schema-analyzer) cmd_on_path spectral && return 0 ;;
        linpeas)
            [[ -x "$INSTALL_PREFIX/linpeas.sh" ]] && return 0
            cmd_on_path linpeas.sh && return 0 ;;
        paramspider)    cmd_on_path paramspider && return 0 ;;
        pacu)           cmd_on_path pacu && return 0 ;;
        prowler)        cmd_on_path prowler && return 0 ;;
        checkov)        cmd_on_path checkov && return 0 ;;
        scout-suite)    cmd_on_path scout && return 0 ;;
        graphql-scanner) cmd_on_path graphqlmap && return 0 ;;
        cloudmapper)    cmd_on_path cloudmapper && return 0 ;;
        dnslog|http-framework-test)
            cmd_on_path python3 && return 0 ;;
    esac

    # go install 产物可能在 ~/go/bin
    if [[ -x "$HOME/go/bin/$cmd" ]]; then
        return 0
    fi

    # 通用二进制检测 (排除包装器命令)
    case "$cmd" in
        python3|/bin/bash|sh|internal:*|'') return 1 ;;
    esac
    cmd_on_path "$cmd"
}

# ----------------------------------------------------------------------------
# 各种安装方法
# ----------------------------------------------------------------------------
have_sudo() {
    [[ -n "$SUDO_CMD" || $EUID -eq 0 ]]
}

install_via_apt() {
    local pkg="$1"
    [[ -z "$pkg" ]] && return 1
    if ! have_sudo; then
        warning "无 root 权限, 跳过 apt 安装: $pkg"
        return 1
    fi
    # 检查包是否已存在
    if log_run $SUDO_CMD apt-cache show "$pkg"; then
        note "apt 安装: $pkg"
        log_run $SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
        return $?
    fi
    return 1
}

# 是否为可尝试安装的包名 (排除包装器/路径/内部命令)
is_installable_name() {
    local n="$1"
    [[ -n "$n" ]] || return 1
    case "$n" in
        python3|/bin/bash|sh|internal:*|*/*|*:*|analyzeHeadless|linpeas.sh)
            return 1 ;;
    esac
    return 0
}

pypi_exists() {
    local pkg="$1"
    [[ -n "$pkg" ]] || return 1
    log_run curl -fsSL "https://pypi.org/pypi/${pkg}/json" -o /dev/null
}

# 依次尝试多个候选名, 去重
try_install_brew() {
    local seen="" c
    for c in "$@"; do
        is_installable_name "$c" || continue
        [[ " $seen " == *" $c "* ]] && continue
        seen="$seen $c"
        install_via_brew "$c" && return 0
    done
    return 1
}

try_install_pip() {
    local explicit="$1" seen="" c
    shift
    # 映射表 pip 列: 直接安装, 不探测 PyPI
    if [[ -n "$explicit" ]] && is_installable_name "$explicit"; then
        install_via_pip "$explicit" && return 0
    fi
    # 自动探测: name / cmd / apt 列, 须在 PyPI 存在
    for c in "$@"; do
        is_installable_name "$c" || continue
        [[ " $seen " == *" $c "* ]] && continue
        seen="$seen $c"
        pypi_exists "$c" || continue
        install_via_pip "$c" && return 0
    done
    return 1
}

install_via_brew() {
    local pkg="$1"
    [[ -z "$pkg" ]] && return 1
    if ! command -v brew >/dev/null 2>&1; then
        return 1
    fi
    if brew list "$pkg" &>/dev/null; then
        note "brew 已安装: $pkg"
        return 0
    fi
    if ! brew info "$pkg" &>/dev/null; then
        return 1
    fi
    note "brew 安装: $pkg"
    log_run brew install "$pkg"
    return $?
}

install_via_pip() {
    local pkg="$1"
    [[ -z "$pkg" ]] && return 1
    note "pip 安装: $pkg"
    PIP_DISABLE_PIP_VERSION_CHECK=1 log_run pip3 install --index-url "$PIP_INDEX_URL" \
        --break-system-packages --quiet "$pkg"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        log_run pip3 install --index-url "$PIP_INDEX_URL" --quiet "$pkg"
        rc=$?
    fi
    return $rc
}

install_via_gem() {
    local pkg="$1"
    [[ -z "$pkg" ]] && return 1
    if ! command -v gem >/dev/null 2>&1; then
        warning "gem 不可用, 跳过: $pkg"
        return 1
    fi
    if ! have_sudo; then
        warning "无 root 权限, 跳过 gem 安装: $pkg"
        return 1
    fi
    note "gem 安装: $pkg"
    log_run $SUDO_CMD gem install "$pkg" --no-document
    return $?
}

install_via_go() {
    local pkg="$1"
    [[ -z "$pkg" ]] && return 1
    if ! command -v go >/dev/null 2>&1; then
        warning "go 未安装, 跳过: $pkg"
        return 1
    fi
    note "go install: $pkg"
    GOPROXY="$GOPROXY" log_run go install "$pkg@latest"
    local rc=$?
    # 确保 ~/go/bin 在 PATH 提示里
    if [[ $rc -eq 0 ]] && [[ -d "$HOME/go/bin" ]]; then
        # 不强行修改用户 shell, 仅提示
        :
    fi
    return $rc
}

install_via_github_release() {
    local repo="$1"
    local cmd="$2"
    [[ -z "$repo" ]] && return 1

    if ! command -v curl >/dev/null 2>&1; then
        warning "curl 未安装, 无法下载 GitHub release"
        return 1
    fi

    if ! have_sudo; then
        warning "无 root 权限, 跳过 GitHub release 安装: $repo"
        return 1
    fi

    note "GitHub release 下载: $repo"

    local platform="${DISTRO_FAMILY:-linux}"
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local tmp
    tmp=$(mktemp -d)
    if ! log_run curl -fsSL "$api" -o "$tmp/release.json"; then
        rm -rf "$tmp"
        return 1
    fi

    local url
    url=$(python3 - "$tmp/release.json" "$platform" <<'PY' 2>/dev/null
import json, re, sys
data = json.load(open(sys.argv[1]))
platform = sys.argv[2]
assets = data.get("assets", [])
if platform == "macos":
    patterns = [
        r'darwin.*arm64', r'macos.*arm64', r'apple.*arm64',
        r'darwin.*amd64', r'macos.*amd64', r'darwin.*x86_64',
        r'darwin', r'macos',
    ]
else:
    patterns = [
        r'linux.*amd64', r'linux.*x86_64', r'linux.*64bit',
        r'.*linux.*x64', r'_linux$', r'linux',
    ]
for p in patterns:
    for a in assets:
        n = a.get("name", "").lower()
        if re.search(p, n) and n.endswith(('.tar.gz', '.tgz', '.zip')):
            print(a["browser_download_url"])
            sys.exit(0)
for a in assets:
    n = a.get("name", "").lower()
    if n.endswith(('.tar.gz', '.tgz', '.zip')):
        print(a["browser_download_url"])
        sys.exit(0)
PY
    )

    if [[ -z "$url" ]]; then
        rm -rf "$tmp"
        warning "未找到合适的 release 资产: $repo (platform=$platform)"
        return 1
    fi

    local fname
    fname=$(basename "$url")
    note "下载: $url"
    if ! log_run curl -fsSL "$url" -o "$tmp/$fname"; then
        rm -rf "$tmp"
        return 1
    fi

    # 解压
    case "$fname" in
        *.tar.gz|*.tgz) tar -xzf "$tmp/$fname" -C "$tmp" 2>/dev/null || { rm -rf "$tmp"; return 1; } ;;
        *.zip)          unzip -q "$tmp/$fname" -d "$tmp"    2>/dev/null || { rm -rf "$tmp"; return 1; } ;;
        *) rm -rf "$tmp"; return 1 ;;
    esac

    # 找可执行文件
    local exec_target=""
    if [[ -n "$cmd" ]]; then
        exec_target=$(find "$tmp" -type f -name "$cmd" -executable 2>/dev/null | head -1)
    fi
    if [[ -z "$exec_target" ]]; then
        # 退一步: 找任意可执行文件
        exec_target=$(find "$tmp" -type f -executable 2>/dev/null \
                      | grep -Ev '\.(md|txt|json|yaml|yml|sum|sha|pem|1)$' \
                      | head -1)
    fi
    if [[ -z "$exec_target" ]]; then
        rm -rf "$tmp"
        warning "解压后未找到可执行文件: $repo"
        return 1
    fi

    log_run $SUDO_CMD install -m 0755 "$exec_target" "$INSTALL_PREFIX/$cmd"
    local rc=$?
    rm -rf "$tmp"
    return $rc
}

install_linpeas_script() {
    # linpeas 是单个 .sh 脚本, 直接 curl 下来放到 /usr/local/bin
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi
    if ! have_sudo; then
        warning "无 root 权限, 跳过 linpeas 下载"
        return 1
    fi
    local tmpdir="${TMPDIR:-/tmp}"
    note "下载 linpeas.sh 到 $INSTALL_PREFIX/"
    if log_run curl -fsSL "https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh" \
        -o "$tmpdir/linpeas.sh"; then
        log_run $SUDO_CMD install -m 0755 "$tmpdir/linpeas.sh" "$INSTALL_PREFIX/linpeas.sh" \
            && { rm -f "$tmpdir/linpeas.sh"; return 0; }
    fi
    log_run curl -fsSL "https://raw.githubusercontent.com/peass-ng/PEASS-ng/master/linPEAS/linpeas.sh" \
        -o "$tmpdir/linpeas.sh" \
        && log_run $SUDO_CMD install -m 0755 "$tmpdir/linpeas.sh" "$INSTALL_PREFIX/linpeas.sh"
    local rc=$?
    rm -f "$tmpdir/linpeas.sh"
    return $rc
}

install_spectral() {
    # spectral 来自 npm
    if ! command -v npm >/dev/null 2>&1; then
        warning "npm 未安装, 无法装 spectral (请先装 Node.js)"
        return 1
    fi
    note "npm 安装: @stoplight/spectral-cli"
    log_run npm install -g @stoplight/spectral-cli
    return $?
}

# ----------------------------------------------------------------------------
# 安装单个工具
# ----------------------------------------------------------------------------
install_tool() {
    local name="$1"
    local cmd
    cmd="$(resolve_cmd "$name")"
    local apt_pkg="${M[$name|apt]:-}"
    local pip_pkg="${M[$name|pip]:-}"
    local gem_pkg="${M[$name|gem]:-}"
    local go_pkg="${M[$name|go]:-}"
    local gh_repo="${M[$name|gh]:-}"
    local note="${M[$name|note]:-}"

    # 跳过内置/内部工具
    if is_builtin_tool "$name"; then
        if [[ -z "$apt_pkg" && -z "$pip_pkg" && -z "$gh_repo" && -z "$go_pkg" ]]; then
            STATUS["$name"]="skip"
            SKIP_REASON["$name"]="内置工具, 运行时由 Python 包装"
            SKIP_COUNT=$((SKIP_COUNT+1))
            return 0
        fi
    fi

    # 已安装
    if is_installed "$name" "$cmd"; then
        if [[ "$MODE" == "install" ]]; then
            STATUS["$name"]="skip"
            SKIP_REASON["$name"]="已存在 ($cmd)"
            SKIP_COUNT=$((SKIP_COUNT+1))
            dim "$name: 已安装 ($cmd)"
        else
            STATUS["$name"]="ok"
            OK_COUNT=$((OK_COUNT+1))
        fi
        return 0
    fi

    if [[ "$MODE" == "check" || "$MODE" == "list" ]]; then
        STATUS["$name"]="fail"
        FAIL_COUNT=$((FAIL_COUNT+1))
        return 0
    fi

    if [[ "$MODE" == "dry-run" ]]; then
        echo "  [DRY] $name (cmd=$cmd) -> apt/brew=$apt_pkg pip=$pip_pkg gem=$gem_pkg go=$go_pkg gh=$gh_repo"
        STATUS["$name"]="dry"
        return 0
    fi

    # 选择安装方法
    local tried=()
    local rc=1

    if [[ -z "$FORCE_METHOD" || "$FORCE_METHOD" == "apt" ]]; then
        if [[ "$PKG_MGR" == "apt" && -n "$apt_pkg" ]]; then
            tried+=("apt")
            install_via_apt "$apt_pkg" && { rc=0; METHOD["$name"]="apt"; }
        fi
    fi

    if [[ $rc -ne 0 && ( -z "$FORCE_METHOD" || "$FORCE_METHOD" == "brew" ) ]]; then
        if [[ "$PKG_MGR" == "brew" ]]; then
            tried+=("brew")
            try_install_brew "$apt_pkg" "$name" "$cmd" && { rc=0; METHOD["$name"]="brew"; }
        fi
    fi

    if [[ $rc -ne 0 && ( -z "$FORCE_METHOD" || "$FORCE_METHOD" == "pip" ) ]]; then
        tried+=("pip")
        try_install_pip "$pip_pkg" "$name" "$cmd" "$apt_pkg" \
            && { rc=0; METHOD["$name"]="pip"; }
    fi

    if [[ $rc -ne 0 && ( -z "$FORCE_METHOD" || "$FORCE_METHOD" == "gem" ) ]]; then
        if [[ -n "$gem_pkg" ]]; then
            tried+=("gem")
            install_via_gem "$gem_pkg" && { rc=0; METHOD["$name"]="gem"; }
        fi
    fi

    if [[ $rc -ne 0 && ( -z "$FORCE_METHOD" || "$FORCE_METHOD" == "go" ) ]]; then
        if [[ -n "$go_pkg" ]]; then
            tried+=("go")
            install_via_go "$go_pkg" && { rc=0; METHOD["$name"]="go"; }
        fi
    fi

    if [[ $rc -ne 0 && ( -z "$FORCE_METHOD" || "$FORCE_METHOD" == "github" ) ]]; then
        if [[ -n "$gh_repo" ]]; then
            tried+=("github")
            install_via_github_release "$gh_repo" "$cmd" && { rc=0; METHOD["$name"]="github"; }
        fi
    fi

    # 特殊情况
    if [[ $rc -ne 0 ]]; then
        case "$name" in
            linpeas)
                install_linpeas_script && { rc=0; METHOD["$name"]="github-script"; }
                ;;
            api-schema-analyzer)
                install_spectral && { rc=0; METHOD["$name"]="npm"; }
                ;;
        esac
    fi

    if [[ $rc -eq 0 ]] && is_installed "$name" "$cmd"; then
        STATUS["$name"]="ok"
        OK_COUNT=$((OK_COUNT+1))
        success "$name 安装成功 (${METHOD[$name]:-unknown})"
        return 0
    fi

    STATUS["$name"]="fail"
    FAIL_COUNT=$((FAIL_COUNT+1))
    if [[ -n "$note" ]]; then
        warning "$name 安装失败 (尝试: ${tried[*]:-无}). 备注: $note"
    else
        warning "$name 安装失败 (尝试: ${tried[*]:-无})"
    fi
    return 1
}

# ----------------------------------------------------------------------------
# 过滤: --only / --skip
# ----------------------------------------------------------------------------
should_handle() {
    local name="$1"
    if [[ -n "$ONLY_TOOLS" ]]; then
        [[ ",$ONLY_TOOLS," == *",$name,"* ]] && return 0 || return 1
    fi
    if [[ -n "$SKIP_TOOLS" ]]; then
        [[ ",$SKIP_TOOLS," == *",$name,"* ]] && return 1 || return 0
    fi
    return 0
}

# ----------------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------------
main() {
    detect_distro
    setup_sudo
    load_map
    discover_tools
    validate_tool_coverage

    echo ""
    echo "============================================================"
    echo "  CyberStrikeAI 工具安装器"
    echo "============================================================"
    note "项目根: $ROOT_DIR"
    note "系统:   $DISTRO_ID (family=$DISTRO_FAMILY, pkg=$PKG_MGR)"
    note "模式:   $MODE"
    note "pip 源: $PIP_INDEX_URL"
    note "go 代理: $GOPROXY"
    if [[ -n "$FORCE_METHOD" ]]; then note "强制方式: $FORCE_METHOD"; fi
    [[ -n "$ONLY_TOOLS" ]] && note "白名单: $ONLY_TOOLS"
    [[ -n "$SKIP_TOOLS"  ]] && note "黑名单: $SKIP_TOOLS"
    if [[ "$DISTRO_FAMILY" == "macos" && "$MODE" == "install" ]]; then
        warning "macOS 无 apt, 将自动尝试: brew → pip(PyPI 探测) → go → GitHub"
    fi
    echo ""

    # 累计工具列表 (按映射表的顺序)
    local names=()
    while IFS='|' read -r name _; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        # 优先用 yaml 里的 (排除 yaml 关闭的)
        if [[ "${YAML_ENABLED[$name]:-true}" == "false" ]]; then
            STATUS["$name"]="skip"
            SKIP_REASON["$name"]="yaml 中 enabled=false"
            continue
        fi
        names+=("$name")
    done < <(get_tool_map)

    TOTAL=${#names[@]}

    if [[ "$MODE" == "list" ]]; then
        info "检测 $TOTAL 个工具状态..."
        echo ""
    else
        info "准备处理 $TOTAL 个工具..."
        echo ""
    fi

    local i=0
    for name in "${names[@]}"; do
        i=$((i+1))
        if ! should_handle "$name"; then
            STATUS["$name"]="skip"
            SKIP_REASON["$name"]="被 --skip / 未在 --only"
            SKIP_COUNT=$((SKIP_COUNT+1))
            continue
        fi
        if [[ "$MODE" != "list" ]]; then
            printf "${GRAY}[%d/%d]${NC} " "$i" "$TOTAL"
        fi
        install_tool "$name"
    done

    if [[ "$MODE" == "list" ]]; then
        echo ""
        echo "  工具名                          | 命令         | 状态      | 说明"
        echo "  --------------------------------+--------------+-----------+--------"
        for name in "${names[@]}"; do
            local cmd note_text st st_color
            cmd="$(resolve_cmd "$name")"
            note_text="${M[$name|note]:-}"
            st="${STATUS[$name]:-?}"
            case "$st" in
                ok)    st_color="${GREEN} OK ${NC}" ;;
                skip)  st_color="${GRAY}SKIP${NC}" ;;
                fail)  st_color="${RED}FAIL${NC}" ;;
                *)     st_color="${YELLOW} ? ${NC}" ;;
            esac
            printf "  %-32s | %-13s| %b | %s\n" "$name" "$cmd" "$st_color" "$note_text"
        done
    fi

    echo ""
    print_summary
}

print_summary() {
    echo "============================================================"
    echo "  安装结果汇总"
    echo "============================================================"
    if [[ "$MODE" == "check" || "$MODE" == "list" ]]; then
        info "总计: $TOTAL | ✅ 已就绪: $OK_COUNT | ⏭  跳过: $SKIP_COUNT | ❌ 缺失: $FAIL_COUNT"
    else
        info "总计: $TOTAL | ✅ 成功: $OK_COUNT | ⏭  跳过: $SKIP_COUNT | ❌ 失败: $FAIL_COUNT"
    fi
    echo ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        note "失败工具:"
        for name in "${!STATUS[@]}"; do
            [[ "${STATUS[$name]}" == "fail" ]] && echo "  - $name"
        done | sort
        echo ""
        note "常见补救:"
        if [[ "$DISTRO_FAMILY" == "macos" ]]; then
            dim "  • macOS: brew install <工具名>  或  pip3 install <工具名>"
            dim "  • 部分工具仅 Kali/apt 提供, macOS 请用 pip/go 或手动安装"
        else
            dim "  • 在 Kali 上先运行: sudo apt update"
        fi
        dim "  • 确认外网可达, 或设置代理: HTTPS_PROXY=http://your-proxy:port"
        dim "  • 大型工具如 ghidra/clair 可手动安装"
        dim "  • API 类工具 (fofa/shodan/zoomeye/quake) 需自行申请并配置 API key"
    fi

    # PATH 提示
    if [[ -d "$HOME/go/bin" ]] && [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
        echo ""
        warning "go install 安装的二进制在: $HOME/go/bin"
        warning "请把它加入 PATH, 例如:  echo 'export PATH=\$HOME/go/bin:\$PATH' >> ~/.bashrc"
    fi
}

main

# check 模式: 有缺失工具时返回非零退出码 (便于 CI)
if [[ "$MODE" == "check" && $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
