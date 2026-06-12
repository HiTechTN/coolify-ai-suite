#!/bin/bash
# lib/common.sh - Bibliothèque partagée pour Coolify AI Suite
# Version: 3.0
#
# Usage: source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

set -euo pipefail

# ============================================
# VERSION
# ============================================
readonly AI_SUITE_VERSION="3.0.0"

# ============================================
# COULEURS (désactivées si --no-color)
# ============================================
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "true" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

# ============================================
# MODE DRY-RUN / FORCE
# ============================================
DRY_RUN=false
FORCE=false

# ============================================
# FICHIERS
# ============================================
readonly AI_SUITE_DIR="/opt/ai-suite"
readonly TRAEFIK_DIR="${AI_SUITE_DIR}/traefik"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_FILE_DEFAULT="/var/log/ai-suite.log"
LOG_FILE="${LOG_FILE:-${LOG_FILE_DEFAULT}}"

# ============================================
# FONCTIONS DE LOGGING
# ============================================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" >&2
    echo "$msg" >> "$LOG_FILE"
}

log_info() {
    log "${CYAN}ℹ${NC} $1"
}

log_success() {
    log "${GREEN}✓${NC} $1"
}

log_warning() {
    log "${YELLOW}⚠${NC} $1"
}

log_error() {
    log "${RED}✗${NC} $1"
}

log_step() {
    local current="$1"
    local total="$2"
    shift 2
    log "${BLUE}[${current}/${total}]${NC} $*"
}

# ============================================
# GESTIONNAIRE D'ERREUR GLOBAL (trap)
# ============================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Le script a échoué avec le code ${exit_code} (ligne ${BASH_LINENO[0]})"
    fi
}

error_handler() {
    local line_no=$1
    local cmd=$2
    local exit_code=$?
    log_error "Erreur à la ligne ${line_no}: '${cmd}' (code: ${exit_code})"
    exit "$exit_code"
}

setup_trap() {
    trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR
    trap cleanup EXIT
}

# ============================================
# VALIDATION ROOT
# ============================================
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root (sudo)"
        exit 1
    fi
}

# ============================================
# AIDE GÉNÉRIQUE
# ============================================
show_common_options() {
    cat << EOF
Options générales :
    -h, --help       Afficher cette aide
    --dry-run        Simuler sans exécuter (affiche les actions)
    --force          Forcer l'exécution (ignore les vérifications)
    --no-color       Désactiver les couleurs
    --log FILE       Écrire les logs dans un fichier (défaut: ${LOG_FILE_DEFAULT})
    --version        Afficher la version
EOF
}

# ============================================
# PARSEUR D'OPTIONS COMMUNES
# ============================================
parse_common_args() {
    local args=("$@")
    local remaining=()

    for arg in "${args[@]}"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --force) FORCE=true ;;
            --no-color) NO_COLOR=true ;;
            --version)
                echo "Coolify AI Suite v${AI_SUITE_VERSION}"
                exit 0
                ;;
            -h|--help)
                if [[ -n "${usage_function:-}" ]]; then
                    "$usage_function"
                fi
                show_common_options
                exit 0
                ;;
            --log)
                ;;
            *)
                remaining+=("$arg")
                ;;
        esac
    done

    # Handle --log with value
    local skip_next=false
    remaining=()
    for ((i=0; i<${#args[@]}; i++)); do
        if $skip_next; then skip_next=false; continue; fi
        if [[ "${args[$i]}" == "--log" ]] && [[ $((i+1)) -lt ${#args[@]} ]]; then
            LOG_FILE="${args[$((i+1))]}"
            skip_next=true
        else
            remaining+=("${args[$i]}")
        fi
    done

    echo "${remaining[@]}"
}

# ============================================
# EXÉCUTION CONDITIONNELLE (dry-run)
# ============================================
run_cmd() {
    local description="$1"
    shift

    log_info "${description}..."

    if $DRY_RUN; then
        log_warning "[DRY-RUN] Commande ignorée : $*"
        return 0
    fi

    "$@"
    log_success "${description} — OK"
}

run_cmd_quiet() {
    local description="$1"
    shift

    if $DRY_RUN; then
        log_info "[DRY-RUN] ${description} : $*"
        return 0
    fi

    "$@" &>/dev/null || true
}

# ============================================
# DOCKER HELPERS
# ============================================
docker_service_running() {
    local name="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"
}

docker_service_exists() {
    local name="$1"
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"
}

require_docker() {
    if ! docker info &>/dev/null; then
        log_error "Docker n'est pas en cours d'exécution"
        exit 1
    fi
}

# ============================================
# RÉSEAU
# ============================================
get_public_ip() {
    curl -s --max-time 10 https://api.ipify.org 2>/dev/null ||
    curl -s --max-time 10 https://ifconfig.me 2>/dev/null ||
    curl -s --max-time 10 https://icanhazip.com 2>/dev/null ||
    hostname -I | awk '{print $1}'
}

get_local_ip() {
    hostname -I | awk '{print $1}'
}

# ============================================
# CHARGEMENT DE LA CONFIG
# ============================================
load_env() {
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi
}

# ============================================
# GÉNÉRATION MOTS DE PASSE
# ============================================
generate_password() {
    local length="${1:-24}"
    openssl rand -base64 "$length" 2>/dev/null | tr -d '\n'
}

generate_secret() {
    local length="${1:-32}"
    openssl rand -hex "$length" 2>/dev/null | tr -d '\n'
}

# ============================================
# TRAEFIK MIDDLEWARE HELPERS
# ============================================
generate_htpasswd() {
    local username="${1:-admin}"
    local password="${2:-}"

    if [[ -z "$password" ]]; then
        password=$(generate_password 16)
    fi

    if command -v htpasswd &>/dev/null; then
        local hash
        hash=$(htpasswd -nbB "$username" "$password" 2>/dev/null | cut -d: -f2)
        echo "${username}:${hash}"
        echo "---PASSWORD:${password}---" >&2
    else
        # Fallback: use openssl (bcrypt not available, use apr1)
        local salt
        salt=$(openssl rand -base64 6 2>/dev/null | tr -d /=+)
        local hash
        hash=$(openssl passwd -apr1 -salt "$salt" "$password" 2>/dev/null)
        echo "${username}:${hash}"
        echo "---PASSWORD:${password}---" >&2
    fi
}

create_traefik_dashboard_middleware() {
    local middleware_file="${TRAEFIK_DIR}/config/middlewares.yml"
    local auth_file="${TRAEFIK_DIR}/config/.htpasswd"

    if [[ ! -f "$auth_file" ]]; then
        log_info "Génération des identifiants pour le dashboard Traefik..."
        local result
        result=$(generate_htpasswd "admin" "")
        local htpasswd_line="${result%%---PASSWORD:*}"
        local password="${result#*---PASSWORD:}"
        password="${password%---*}"

        echo "$htpasswd_line" > "$auth_file"
        chmod 600 "$auth_file"

        # Stocker le mot de passe dans .env
        local env_file="${SCRIPT_DIR}/.env"
        if [[ -f "$env_file" ]]; then
            if grep -q "TRAEFIK_DASHBOARD_PASSWORD" "$env_file" 2>/dev/null; then
                sed -i "s/^TRAEFIK_DASHBOARD_PASSWORD=.*/TRAEFIK_DASHBOARD_PASSWORD=${password}/" "$env_file"
            else
                echo "TRAEFIK_DASHBOARD_PASSWORD=${password}" >> "$env_file"
            fi
        fi

        log_warning "Dashboard Traefik: user=admin password=${password}"
        log_info "Connectez-vous sur http://$(get_local_ip):8080 avec ces identifiants"
    fi

    cat > "$middleware_file" << MIDDLEWARE_EOF
http:
  middlewares:
    dashboard-auth:
      basicAuth:
        usersFile: /config/.htpasswd

    secHeaders:
      headers:
        frameDeny: true
        sslRedirect: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000

    rate-limit:
      rateLimit:
        average: 100
        burst: 50
        period: 1m
        sourceCriterion:
          ipStrategy:
            depth: 1
MIDDLEWARE_EOF

    chmod 600 "$middleware_file"
    log_success "Middlewares Traefik configurés (auth, security headers, rate limit)"
}

# ============================================
# GPU DETECTION
# ============================================
detect_nvidia_gpu() {
    if command -v nvidia-smi &>/dev/null; then
        local gpu_info
        gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
        if [[ -n "$gpu_info" ]]; then
            echo "$gpu_info"
            return 0
        fi
    fi

    if lspci 2>/dev/null | grep -qi "nvidia"; then
        echo "NVIDIA GPU détectée (drivers non chargés)"
        return 0
    fi

    return 1
}

detect_nvidia_runtime() {
    if docker info 2>/dev/null | grep -q "nvidia"; then
        return 0
    fi
    return 1
}

# ============================================
# DOCKER IMAGE VERSION CHECK
# ============================================
get_container_image() {
    local container="$1"
    docker inspect "$container" --format '{{.Config.Image}}' 2>/dev/null || echo ""
}

get_container_uptime() {
    local container="$1"
    docker inspect "$container" --format '{{.State.StartedAt}}' 2>/dev/null || echo ""
}

# ============================================
# NOTIFICATIONS
# ============================================
send_notification() {
    local subject="$1"
    local message="$2"

    # Email via sendmail ou mail
    if command -v mail &>/dev/null && [[ -n "${NOTIFICATION_EMAIL:-}" ]]; then
        echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL" 2>/dev/null || true
    fi

    # Telegram bot
    if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        local text
        text="${subject}%0A%0A${message}"
        curl -s --max-time 5 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id=${TELEGRAM_CHAT_ID}&text=${text}" >/dev/null 2>&1 || true
    fi

    # Discord webhook
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        curl -s --max-time 5 -H "Content-Type: application/json" \
            -d "{\"content\": \"**${subject}**\n${message}\"}" \
            "${DISCORD_WEBHOOK}" >/dev/null 2>&1 || true
    fi
}
