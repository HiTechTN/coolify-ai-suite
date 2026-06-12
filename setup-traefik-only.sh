#!/bin/bash
# setup-traefik-only.sh - Ajouter HTTPS/Traefik à une installation existante
# Author: Mohamed Azmi KAANICHE
# Version: 2.0
#
# Usage: sudo ./setup-traefik-only.sh [options]
#
# Options:
#   -h, --help       Afficher cette aide
#   --dry-run        Simuler sans modifier
#   --force          Forcer la reconfiguration
#   --no-color       Désactiver les couleurs
#   --log FILE       Fichier de log
#   --version        Afficher la version
#
# Variables d'environnement:
#   DOMAIN, SSL_EMAIL, HTTP_PORT, HTTPS_PORT

set -euo pipefail

# ============================================
# SOURCE DES BIBLIOTHÈQUES
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

LOG_FILE="/var/log/ai-suite-traefik.log"
HTTP_PORT="${TRAEFIK_HTTP_PORT:-80}"
HTTPS_PORT="${TRAEFIK_HTTPS_PORT:-443}"

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    setup-traefik-only.sh — Ajouter HTTPS/Traefik à une installation existante

${BOLD}SYNOPSIS${NC}
    sudo ./setup-traefik-only.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Configure et déploie Traefik avec HTTPS automatique sur les services
    existants de la AI Suite. Peut être exécuté après l'installation
    initiale si HTTPS n'a pas été configuré.

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --dry-run        Simuler sans modifier
    --force          Forcer la reconfiguration
    --no-color       Désactiver les couleurs
    --log FILE       Fichier de log
    --version        Afficher la version

${BOLD}EXEMPLE${NC}
    sudo ./setup-traefik-only.sh
    sudo DOMAIN=hitech.tn ./setup-traefik-only.sh --dry-run
EOF
}

usage_function=usage

# ============================================
# PARSE DES ARGUMENTS
# ============================================
parse_args() {
    local args=("$@")

    for arg in "${args[@]}"; do
        case "$arg" in
            -h|--help) usage; show_common_options; exit 0 ;;
            --version) echo "Coolify AI Suite v${AI_SUITE_VERSION}"; exit 0 ;;
        esac
    done

    local remaining
    remaining=$(parse_common_args "$@")

    if [[ -n "$remaining" ]]; then
        log_error "Argument inconnu: ${remaining}"
        usage
        exit 1
    fi
}

# ============================================
# FONCTIONS
# ============================================
add_traefik_labels() {
    local compose_file="$1"
    local service_name="$2"
    local hostname="$3"

    if [[ ! -f "$compose_file" ]]; then
        log_warning "Fichier non trouvé: ${compose_file}"
        return
    fi

    if grep -q "traefik.enable" "$compose_file"; then
        log_info "${service_name} : labels Traefik déjà présents"
        return
    fi

    log_info "Ajout des labels Traefik à ${service_name}..."

    if $DRY_RUN; then
        log_warning "[DRY-RUN] Ajout des labels sur ${compose_file}"
        return
    fi

    # Créer une version HEADER + nouveau contenu
    local tmp_file
    tmp_file=$(mktemp)

    cat > "$tmp_file" << LABELS_EOF
      - "traefik.enable=true"
      - "traefik.http.routers.${service_name}.rule=Host(\`${hostname}.${TLD}\`)"
      - "traefik.http.routers.${service_name}.tls=true"
LABELS_EOF

    # Insérer les labels après la ligne "labels:"
    sed -i "/^labels:/r ${tmp_file}" "$compose_file"
    rm -f "$tmp_file"

    log_success "${service_name} : labels ajoutés"
}

main() {
    setup_trap
    parse_args "$@"
    require_root
    require_docker
    load_env

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Ajout de Traefik/HTTPS à l'installation       ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""

    # Demander le domaine si non fourni
    if [[ -z "${DOMAIN:-}" ]]; then
        read -p "Nom de domaine (ex: hitech.tn, laisser vide pour .local): " input_domain
        DOMAIN="${input_domain:-}"
        if [[ -n "$DOMAIN" ]]; then
            read -p "Email Let's Encrypt (ex: admin@${DOMAIN}): " input_email
            SSL_EMAIL="${input_email:-admin@${DOMAIN}}"
        fi
    fi

    # Créer le réseau
    run_cmd "Création du réseau Docker '$NETWORK_NAME'" \
        bash -c "docker network create '$NETWORK_NAME' 2>/dev/null || true"

    # Créer les dossiers
    run_cmd "Création des dossiers Traefik" \
        mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}

    # Configuration Traefik
    cat > "$TRAEFIK_DIR/traefik.yml" << TRAEFIK_EOF
global:
  checkNewVersion: true
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: true

log:
  level: INFO

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${SSL_EMAIL}
      storage: /acme/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: ${NETWORK_NAME}
TRAEFIK_EOF
    log_success "traefik.yml créé"

    # Middlewares (auth, rate limit, security headers)
    create_traefik_dashboard_middleware

    # Config dynamique si domaine fourni
    if [[ -n "$DOMAIN" ]]; then
        cat > "$TRAEFIK_DIR/config/dynamic-config.yml" << DYNAMIC_EOF
http:
  routers:
    code-server:
      rule: "Host(\`code.${DOMAIN}\`)"
      service: code-server
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      middlewares:
        - secHeaders
        - rate-limit

    open-webui:
      rule: "Host(\`chat.${DOMAIN}\`)"
      service: open-webui
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      middlewares:
        - secHeaders
        - rate-limit

    ollama:
      rule: "Host(\`ollama.${DOMAIN}\`)"
      service: ollama
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      middlewares:
        - secHeaders
        - rate-limit

  services:
    code-server:
      loadBalancer:
        servers:
          - url: "http://code-server:8443"
        healthCheck:
          path: /health
          interval: 30s
          timeout: 3s

    open-webui:
      loadBalancer:
        servers:
          - url: "http://open-webui:8080"
        healthCheck:
          path: /health
          interval: 30s
          timeout: 3s

    ollama:
      loadBalancer:
        servers:
          - url: "http://ollama:11434"
        healthCheck:
          path: /
          interval: 30s
          timeout: 3s

tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
DYNAMIC_EOF
        log_success "Config dynamique créée pour le domaine ${DOMAIN}"
    fi

    # Labels pour les services existants
    add_traefik_labels "/opt/ai-suite/code-server/docker-compose.yml" "code-server" "code"
    add_traefik_labels "/opt/ai-suite/ollama/docker-compose.yml" "ollama" "ollama"
    add_traefik_labels "/opt/ai-suite/open-webui/docker-compose.yml" "open-webui" "chat"

    # Docker Compose Traefik
    cat > "$TRAEFIK_DIR/docker-compose.yml" << COMPOSE_EOF
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    command:
      - "--configfile=/traefik.yml"
    ports:
      - "${HTTP_PORT}:80"
      - "${HTTPS_PORT}:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config:/config
      - ./acme:/acme
      - ./traefik.yml:/traefik.yml
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`traefik.${DOMAIN}\`) || (Host(\`localhost\`) && PathPrefix(\`/api\`))"
      - "traefik.http.routers.api.service=api@internal"
      - "traefik.http.routers.api.middlewares=dashboard-auth"
      - "traefik.http.routers.api.tls=true"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  ${NETWORK_NAME}:
    external: true
COMPOSE_EOF
    log_success "docker-compose.yml créé"

    # Pare-feu
    run_cmd "Ouverture des ports HTTP/HTTPS" \
        bash -c "ufw allow ${HTTP_PORT}/tcp 2>/dev/null; ufw allow ${HTTPS_PORT}/tcp 2>/dev/null; true"

    # Démarrer Traefik
    run_cmd "Démarrage de Traefik" bash -c "cd '$TRAEFIK_DIR' && docker compose up -d"

    # Exporter la config
    if [[ -n "$DOMAIN" ]]; then
        cat > "$SCRIPT_DIR/.env" << ENV_EOF
DOMAIN=${DOMAIN}
SSL_EMAIL=${SSL_EMAIL}
NETWORK_NAME=${NETWORK_NAME}
AI_SUITE_DIR=${AI_SUITE_DIR}
ENV_EOF
        chmod 600 "$SCRIPT_DIR/.env" 2>/dev/null || true
    fi

    # Résumé
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Traefik configuré avec succès !${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    if [[ -n "$DOMAIN" ]]; then
        echo -e "${BOLD}Accès HTTPS :${NC}"
        echo -e "  • Code-Server: https://code.${DOMAIN}"
        echo -e "  • Open WebUI:  https://chat.${DOMAIN}"
        echo -e "  • Ollama API:  https://ollama.${DOMAIN}"
        echo ""
        echo -e "${BOLD}Configuration DNS requise :${NC}"
        echo -e "  A      ${DOMAIN}    → $(get_local_ip)"
        echo -e "  A      *.${DOMAIN}  → $(get_local_ip)"
    else
        echo -e "${BOLD}Accès HTTPS (développement) :${NC}"
        echo -e "  Modifiez /etc/hosts : $(get_local_ip) code-server.local chat.local ollama.local"
    fi
    echo ""
    echo -e "${BOLD}Dashboard Traefik :${NC} http://$(get_local_ip):8080"
    echo ""
}

main "$@"
