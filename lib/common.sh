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
_COMMON_REMAINING=""

# ============================================
# FICHIERS
# ============================================
AI_SUITE_DIR="${AI_SUITE_DIR:-/opt/ai-suite}"
TRAEFIK_DIR="${AI_SUITE_DIR}/traefik"
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

    # Handle --log with value; skip already-handled flags
    local skip_next=false
    remaining=()
    for ((i=0; i<${#args[@]}; i++)); do
        if $skip_next; then skip_next=false; continue; fi
        case "${args[$i]}" in
            --log)
                if [[ $((i+1)) -lt ${#args[@]} ]]; then
                    LOG_FILE="${args[$((i+1))]}"
                    skip_next=true
                fi
                ;;
            --dry-run|--force|--no-color|-h|--help|--version) ;;
            *)
                remaining+=("${args[$i]}")
                ;;
        esac
    done

    _COMMON_REMAINING="${remaining[*]}"
    printf '%s\n' "${remaining[@]}"
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
# DDNS — MISE À JOUR DYNAMIQUE DNS (Cloudflare)
# ============================================

# Appel API Cloudflare (retourne le JSON brut)
cloudflare_api() {
    local endpoint="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    curl -s --max-time 15 \
        -X "$method" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/${endpoint}" \
        ${data:+-d "$data"}
}

# Met à jour (ou crée) un enregistrement DNS A sur Cloudflare
cloudflare_update_dns_a() {
    local name="$1"
    local ip="$2"
    local zone_id="$3"
    local record_id

    # Chercher l'enregistrement A existant
    record_id=$(cloudflare_api "zones/${zone_id}/dns_records?type=A&name=${name}" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else '')" 2>/dev/null || echo "")

    if [[ -n "$record_id" ]]; then
        cloudflare_api "zones/${zone_id}/dns_records/${record_id}" PUT \
            "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0) if d.get('success') else exit(1)" 2>/dev/null
    else
        cloudflare_api "zones/${zone_id}/dns_records" POST \
            "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":false}" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0) if d.get('success') else exit(1)" 2>/dev/null
    fi
}

# Résout le nom de domaine en IP (vérification)
resolve_to_ip() {
    local domain="$1"
    dig +short "$domain" A 2>/dev/null | head -1 || host "$domain" 2>/dev/null | grep "has address" | awk '{print $NF}' | head -1
}

# Récupère le Zone ID Cloudflare à partir du domaine
cloudflare_get_zone_id() {
    local domain="$1"
    cloudflare_api "zones?name=${domain}" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else '')" 2>/dev/null || echo ""
}

# Vérifie que le token Cloudflare est valide
cloudflare_verify_token() {
    cloudflare_api "user/tokens/verify" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); exit(0) if d.get('success') else exit(1)" 2>/dev/null
}

# Point d'entrée principal DDNS : compare IP publique et DNS, met à jour si différent
ddns_update() {
    local domain="$1"
    local public_ip="$2"
    local provider="${DDNS_PROVIDER:-cloudflare}"
    local updated=false

    case "$provider" in
        cloudflare)
            if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
                log_error "CLOUDFLARE_API_TOKEN non défini dans .env"
                return 1
            fi
            local zone_id="${CLOUDFLARE_ZONE_ID:-}"
            if [[ -z "$zone_id" ]]; then
                log_info "Récupération automatique du Zone ID Cloudflare..."
                zone_id=$(cloudflare_get_zone_id "$domain")
                if [[ -z "$zone_id" ]]; then
                    log_error "Impossible de récupérer le Zone ID pour ${domain}. Vérifiez votre token API."
                    return 1
                fi
                CLOUDFLARE_ZONE_ID="$zone_id"
            fi

            # Mettre à jour l'enregistrement A du domaine principal
            local dns_ip
            dns_ip=$(resolve_to_ip "$domain")
            if [[ "$dns_ip" != "$public_ip" ]]; then
                log_info "Mise à jour de ${domain} : ${dns_ip:-vide} → ${public_ip}"
                if cloudflare_update_dns_a "$domain" "$public_ip" "$zone_id"; then
                    log_success "DNS mis à jour : ${domain} → ${public_ip}"
                    updated=true
                else
                    log_error "Échec mise à jour DNS pour ${domain}"
                fi
            else
                log_info "Aucun changement pour ${domain} (déjà ${public_ip})"
            fi

            # Mettre à jour l'enregistrement A du wildcard *.domain
            local wildcard_ip
            wildcard_ip=$(resolve_to_ip "*.${domain}")
            if [[ "$wildcard_ip" != "$public_ip" ]]; then
                log_info "Mise à jour de *.${domain} : ${wildcard_ip:-vide} → ${public_ip}"
                if cloudflare_update_dns_a "*.${domain}" "$public_ip" "$zone_id"; then
                    log_success "DNS mis à jour : *.${domain} → ${public_ip}"
                    updated=true
                else
                    log_error "Échec mise à jour DNS pour *.${domain}"
                fi
            else
                log_info "Aucun changement pour *.${domain} (déjà ${public_ip})"
            fi

            if $updated; then
                send_notification "DDNS mis à jour" "IP publique ${public_ip} propagée vers ${domain}"
            fi
            ;;
        *)
            log_error "Fournisseur DDNS non supporté : ${provider}"
            return 1
            ;;
    esac
}

# Assistant interactif de configuration Cloudflare
setup_cloudflare_ddns() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Configuration DDNS — Cloudflare${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Avant de commencer, assurez-vous d'avoir :"
    echo -e "  1. Un compte Cloudflare (https://dash.cloudflare.com)"
    echo -e "  2. ${BOLD}${DOMAIN:-votre-domaine}${NC} ajouté à Cloudflare"
    echo -e "  3. Les nameservers Ooredoo changés pour ceux de Cloudflare"
    echo ""
    echo -e "Pour créer un token : Dashboard Cloudflare → Mon Profil → Tokens API → Créer"
    echo -e "Permission minimale : ${BOLD}Zone.DNS:Edit${NC}"
    echo ""

    local api_token
    local env_file="${SCRIPT_DIR}/.env"
    [[ -f "$env_file" ]] || touch "$env_file"

    read -s -p "Token API Cloudflare : " api_token
    echo ""

    if [[ -z "$api_token" ]]; then
        log_error "Token requis"
        return 1
    fi

    # Vérifier le token
    log_info "Vérification du token..."
    CLOUDFLARE_API_TOKEN="$api_token"
    if ! cloudflare_verify_token; then
        log_error "Token invalide. Vérifiez qu'il a les permissions Zone.DNS:Edit"
        return 1
    fi
    log_success "Token valide"

    # Récupérer le Zone ID
    local zone_id
    zone_id=$(cloudflare_get_zone_id "${DOMAIN:-}")
    if [[ -z "$zone_id" ]]; then
        log_warning "Zone ID non trouvé pour ${DOMAIN:-}. Vérifiez que le domaine est ajouté à Cloudflare."
        echo -e "Entrez le Zone ID manuellement (Dashboard → Aperçu → ID de zone) :"
        read -r zone_id
    fi

    # Enregistrer dans .env
    if grep -q "^CLOUDFLARE_API_TOKEN=" "$env_file" 2>/dev/null; then
        sed -i "s/^CLOUDFLARE_API_TOKEN=.*/CLOUDFLARE_API_TOKEN=${api_token}/" "$env_file"
    else
        echo "" >> "$env_file"
        echo "# Cloudflare DDNS (ajouté par setup-ddns)" >> "$env_file"
        echo "CLOUDFLARE_API_TOKEN=${api_token}" >> "$env_file"
    fi

    if [[ -n "$zone_id" ]]; then
        if grep -q "^CLOUDFLARE_ZONE_ID=" "$env_file" 2>/dev/null; then
            sed -i "s/^CLOUDFLARE_ZONE_ID=.*/CLOUDFLARE_ZONE_ID=${zone_id}/" "$env_file"
        else
            echo "CLOUDFLARE_ZONE_ID=${zone_id}" >> "$env_file"
        fi
    fi

    # Activer DDNS
    if grep -q "^DDNS_ENABLED=" "$env_file" 2>/dev/null; then
        sed -i "s/^DDNS_ENABLED=.*/DDNS_ENABLED=true/" "$env_file"
    else
        echo "DDNS_ENABLED=true" >> "$env_file"
    fi
    if grep -q "^DDNS_PROVIDER=" "$env_file" 2>/dev/null; then
        sed -i "s/^DDNS_PROVIDER=.*/DDNS_PROVIDER=cloudflare/" "$env_file"
    else
        echo "DDNS_PROVIDER=cloudflare" >> "$env_file"
    fi

    chmod 600 "$env_file"
    log_success "Configuration Cloudflare enregistrée dans .env"

    # Test de mise à jour
    echo ""
    echo -e "Souhaitez-vous tester la mise à jour DNS maintenant ?"
    read -p "Tester la mise à jour ? (O/n): " test_now
    if [[ "$test_now" != "n" && "$test_now" != "N" ]]; then
        local public_ip
        public_ip=$(get_public_ip)
        if [[ -n "$public_ip" ]]; then
            ddns_update "${DOMAIN:-}" "$public_ip"
        fi
    fi

    # Proposer l'installation du cron
    echo ""
    echo -e "Installer une tâche cron pour la vérification automatique toutes les 5 minutes ?"
    read -p "Installer cron ? (O/n): " install_cron
    if [[ "$install_cron" != "n" && "$install_cron" != "N" ]]; then
        install_ddns_cron
    fi

    echo ""
    log_success "Configuration DDNS terminée"
}

# Installation de la tâche cron pour DDNS
install_ddns_cron() {
    local script_path="${SCRIPT_DIR}/check-public-ip.sh"
    local cron_cmd="*/5 * * * * ${script_path} --ddns --cron >> /var/log/ai-suite-ddns.log 2>&1"

    if crontab -l 2>/dev/null | grep -q "check-public-ip.sh --ddns"; then
        log_info "Tâche cron DDNS déjà installée"
        return 0
    fi

    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    log_success "Cron installé : vérification DDNS toutes les 5 minutes"
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
