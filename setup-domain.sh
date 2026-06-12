#!/bin/bash
# setup-domain.sh - Configurer un domaine réel pour Coolify AI Suite
# Author: Mohamed Azmi KAANICHE
# Version: 2.0
#
# Usage: sudo ./setup-domain.sh [options]
#
# Options:
#   -h, --help       Afficher cette aide
#   --dry-run        Simuler sans modifier
#   --force          Ignorer les vérifications
#   --no-color       Désactiver les couleurs
#   --log FILE       Fichier de log
#   --version        Afficher la version
#
# Variables d'environnement:
#   DOMAIN, SSL_EMAIL

set -euo pipefail

# ============================================
# SOURCE DES BIBLIOTHÈQUES
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

LOG_FILE="/var/log/ai-suite-domain.log"

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    setup-domain.sh — Configurer un nom de domaine avec SSL pour la AI Suite

${BOLD}SYNOPSIS${NC}
    sudo ./setup-domain.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Configure un nom de domaine réel (ex: hitech.tn) avec certificats SSL
    automatiques Let's Encrypt pour tous les services de la AI Suite.
    Sous-domaines créés : code.*, chat.*, ollama.*, coolify.*

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --dry-run        Simuler sans modifier
    --force          Ignorer les vérifications DNS
    --no-color       Désactiver les couleurs
    --log FILE       Fichier de log
    --version        Afficher la version

${BOLD}EXEMPLE${NC}
    sudo ./setup-domain.sh
    sudo DOMAIN=hitech.tn SSL_EMAIL=admin@hitech.tn ./setup-domain.sh --dry-run
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
prompt_config() {
    clear
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Configuration du Nom de Domaine               ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""

    local ip
    ip=$(get_public_ip)
    echo -e "${BOLD}IP publique détectée :${NC} $ip"
    echo ""

    if [[ -z "${DOMAIN:-}" ]]; then
        read -p "Nom de domaine (ex: hitech.tn): " DOMAIN
        DOMAIN="${DOMAIN:-hitech.tn}"
    else
        echo -e "Domaine: ${BOLD}${DOMAIN}${NC}"
    fi

    if [[ -z "${SSL_EMAIL:-}" ]]; then
        read -p "Email Let's Encrypt (ex: admin@${DOMAIN}): " SSL_EMAIL
        SSL_EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"
    else
        echo -e "Email SSL: ${BOLD}${SSL_EMAIL}${NC}"
    fi

    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Instructions DNS                              ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Ajoutez ces enregistrements chez votre registrar :"
    echo ""
    echo -e "  ${BOLD}Type${NC}  ${BOLD}Nom${NC}               ${BOLD}Valeur${NC}"
    echo -e "  ───────────────────────────────────────────"
    echo -e "  ${CYAN}A${NC}     ${DOMAIN}          ${ip}"
    echo -e "  ${CYAN}A${NC}     *.${DOMAIN}        ${ip}"
    echo ""

    # Vérification DNS
    if command -v dig &>/dev/null; then
        local resolved
        resolved=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
        if [[ -n "$resolved" ]]; then
            log_success "DNS vérifié: ${DOMAIN} → ${resolved}"
            if [[ "$resolved" != "$ip" ]]; then
                log_warning "⚠ L'IP DNS (${resolved}) diffère de l'IP publique (${ip})"
                if ! $FORCE; then
                    log_warning "Utilisez --force pour ignorer cette vérification"
                    log_warning "Ou attendez la propagation DNS avant de continuer"
                fi
            fi
        else
            log_warning "Impossible de vérifier le DNS pour ${DOMAIN}"
            log_warning "Continuez si la propagation est en cours, ou utilisez --force"
        fi
    else
        log_warning "dig non installé, vérification DNS ignorée"
    fi

    if ! $DRY_RUN && ! $FORCE; then
        read -p "Continuer ? (O/n): " confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            log_info "Installation annulée"
            exit 0
        fi
    fi
}

prepare_system() {
    log "Préparation du système..."

    run_cmd "Création du réseau Docker" \
        bash -c "docker network create '$NETWORK_NAME' 2>/dev/null || true"

    run_cmd "Création des dossiers Traefik" \
        mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}

    # Libérer le port 80 si donbosco_nginx l'utilise
    if docker_service_running "donbosco_nginx"; then
        log_warning "donbosco_nginx utilise le port 80 — reconfiguration vers 8081"
        run_cmd "Reconfiguration de donbosco_nginx (80 → 8081)" \
            bash -c "
                nginx_compose=\$(docker inspect donbosco_nginx --format '{{index .Config.Labels \"com.docker.compose.project.config_files\"}}' 2>/dev/null || echo '')
                if [[ -f \"\$nginx_compose\" ]]; then
                    sed -i 's/\"80:80\"/\"8081:80\"/g; s/80:80/8081:80/g' \"\$nginx_compose\"
                    cd \"\$(dirname \"\$nginx_compose\")\" && docker compose up -d 2>/dev/null || true
                fi
            "
    fi

    if command -v ufw &>/dev/null; then
        run_cmd "Ouverture des ports 80/443" \
            bash -c "ufw allow 80/tcp 2>/dev/null; ufw allow 443/tcp 2>/dev/null; true"
    fi
}

deploy_traefik() {
    log "Déploiement de Traefik avec le domaine ${DOMAIN}..."

    mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}

    # Sauvegarde de l'ancienne config
    if [[ -f "$TRAEFIK_DIR/traefik.yml" ]] && ! $DRY_RUN; then
        local backup_file="${TRAEFIK_DIR}/traefik.yml.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$TRAEFIK_DIR/traefik.yml" "$backup_file"
        log_info "Ancienne configuration sauvegardée: ${backup_file}"
    fi

    cat > "$TRAEFIK_DIR/traefik.yml" << TRAEFIK_EOF
global:
  checkNewVersion: true
  sendAnonymousUsage: false

api:
  dashboard: true

log:
  level: INFO
  filePath: /var/log/traefik/traefik.log

accessLog:
  filePath: /var/log/traefik/access.log

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
  file:
    directory: /config
    watch: true
TRAEFIK_EOF

    # Middlewares (auth, rate limit, security headers)
    create_traefik_dashboard_middleware

    # Règles dynamiques
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

    coolify:
      rule: "Host(\`coolify.${DOMAIN}\`)"
      service: coolify
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      middlewares:
        - secHeaders
        - rate-limit

DYNAMIC_EOF

    # Ajout donbosco si présent
    if docker_service_running "donbosco_nginx"; then
        local nginx_ip
        nginx_ip=$(docker inspect donbosco_nginx --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$conf.IPAddress}}{{"\n"}}{{end}}' 2>/dev/null | head -1)
        if [[ -n "$nginx_ip" ]]; then
            cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << DONBOSCO_EOF
    donbosco:
      rule: "Host(\`donbosco.${DOMAIN}\`)"
      service: donbosco
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

DONBOSCO_EOF
        fi
    fi

    # Services
    cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << SERVICES_EOF
  services:
    code-server:
      loadBalancer:
        servers:
          - url: "http://code-server:8443"

    open-webui:
      loadBalancer:
        servers:
          - url: "http://open-webui:8080"

    ollama:
      loadBalancer:
        servers:
          - url: "http://ollama:11434"

    coolify:
      loadBalancer:
        servers:
          - url: "http://coolify:8080"

SERVICES_EOF

    if [[ -n "${nginx_ip:-}" ]]; then
        cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << DONBOSCO_SVC_EOF
    donbosco:
      loadBalancer:
        servers:
          - url: "http://${nginx_ip}:80"

DONBOSCO_SVC_EOF
    fi

    cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << TLS_EOF
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
TLS_EOF

    # Docker Compose Traefik
    cat > "$TRAEFIK_DIR/docker-compose.yml" << COMPOSE_EOF
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    command:
      - "--configfile=/traefik.yml"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config:/config
      - ./acme:/acme
      - ./logs:/var/log/traefik
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

    run_cmd "Démarrage de Traefik" bash -c "cd '$TRAEFIK_DIR' && docker compose up -d"
}

update_services() {
    log "Mise à jour des services avec le domaine ${DOMAIN}..."

    # Code-Server
    if [[ -f "$AI_SUITE_DIR/code-server/docker-compose.yml" ]]; then
        sed -i "s/Host(\`code\..*\`)/Host(\`code.${DOMAIN}\`)/g" \
            "$AI_SUITE_DIR/code-server/docker-compose.yml"
        log_success "Code-Server mis à jour pour code.${DOMAIN}"
    fi

    # Ollama
    if [[ -f "$AI_SUITE_DIR/ollama/docker-compose.yml" ]]; then
        sed -i "s/Host(\`ollama\..*\`)/Host(\`ollama.${DOMAIN}\`)/g" \
            "$AI_SUITE_DIR/ollama/docker-compose.yml"
        log_success "Ollama mis à jour pour ollama.${DOMAIN}"
    fi

    # Open WebUI
    if [[ -f "$AI_SUITE_DIR/open-webui/docker-compose.yml" ]]; then
        sed -i "s/Host(\`chat\..*\`)/Host(\`chat.${DOMAIN}\`)/g" \
            "$AI_SUITE_DIR/open-webui/docker-compose.yml"
        log_success "Open WebUI mis à jour pour chat.${DOMAIN}"
    fi

    # Redémarrer les services
    for service_dir in "$AI_SUITE_DIR"/code-server "$AI_SUITE_DIR"/ollama "$AI_SUITE_DIR"/open-webui; do
        if [[ -f "$service_dir/docker-compose.yml" ]]; then
            run_cmd "Redémarrage de $(basename "$service_dir")" \
                bash -c "cd '$service_dir' && docker compose up -d"
        fi
    done
}

connect_existing_services() {
    log "Connexion des services existants au réseau ${NETWORK_NAME}..."

    for container in coolify donbosco_nginx donbosco_api; do
        if docker_service_running "$container"; then
            run_cmd_quiet "Connexion de ${container}" \
                docker network connect "$NETWORK_NAME" "$container" 2>/dev/null || true
        fi
    done
}

setup_ssl_renewal() {
    log "Configuration du renouvellement SSL..."

    cat > "$TRAEFIK_DIR/renew-ssl.sh" << 'RENEW_EOF'
#!/bin/bash
docker exec traefik traefik certificates rotate
echo "$(date): Certificats renouvelés" >> /var/log/ssl-renewal.log
RENEW_EOF
    chmod +x "$TRAEFIK_DIR/renew-ssl.sh"

    if ! crontab -l 2>/dev/null | grep -q "renew-ssl"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * $TRAEFIK_DIR/renew-ssl.sh >> /var/log/ssl-renewal.log 2>&1") | crontab -
    fi
}

export_config() {
    cat > "$SCRIPT_DIR/.env" << ENV_EOF
DOMAIN=${DOMAIN}
SSL_EMAIL=${SSL_EMAIL}
OLLAMA_PORT=${OLLAMA_PORT:-11434}
CODE_SERVER_PORT=${CODE_SERVER_PORT:-8443}
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT:-3000}
COOLIFY_PORT=${COOLIFY_PORT:-8000}
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443
NETWORK_NAME=${NETWORK_NAME}
AI_SUITE_DIR=${AI_SUITE_DIR}
BACKUP_DIR=${BACKUP_DIR}
RETENTION_DAYS=${RETENTION_DAYS}
TZ=${TZ}
ENV_EOF
    chmod 600 "$SCRIPT_DIR/.env"
    log_success "Configuration exportée dans .env"
}

show_summary() {
    local ip
    ip=$(get_public_ip)

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Configuration du domaine terminée avec succès !${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}Accès aux services :${NC}"
    echo -e "  • Coolify:      https://coolify.${DOMAIN}"
    echo -e "  • Code-Server:  https://code.${DOMAIN}"
    echo -e "  • Ollama API:   https://ollama.${DOMAIN}"
    echo -e "  • Open WebUI:   https://chat.${DOMAIN}"
    if docker_service_running "donbosco_nginx"; then
        echo -e "  • Don Bosco:    https://donbosco.${DOMAIN}"
    fi
    echo ""
    echo -e "${BOLD}Traefik Dashboard :${NC} http://${ip}:8080"
    echo ""
    echo -e "${BOLD}${YELLOW}Prochaines étapes :${NC}"
    echo -e "  1. Vérifiez: docker logs traefik | grep -i certificate"
    echo -e "  2. Ajoutez de nouveaux projets: https://monservice.${DOMAIN}"
    echo ""
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    setup_trap
    parse_args "$@"
    require_root
    require_docker
    load_env

    prompt_config
    prepare_system
    deploy_traefik
    update_services
    connect_existing_services
    setup_ssl_renewal
    export_config
    show_summary
}

main "$@"
