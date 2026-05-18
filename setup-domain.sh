#!/bin/bash
# setup-domain.sh - Configurer un domaine réel pour Coolify AI Suite
# Author: Mohamed Azmi KAANICHE
# Version: 1.0
#
# Usage: sudo ./setup-domain.sh
# Ce script configure un nom de domaine (ex: hitech.tn) avec SSL automatique
# pour tous les services de la Coolify AI Suite.

set -euo pipefail

# ============================================
# COULEURS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================
# CONFIGURATION
# ============================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/ai-suite-domain.log"
readonly NETWORK_NAME="${NETWORK_NAME:-ai-suite}"
readonly TRAEFIK_DIR="${TRAEFIK_DIR:-/opt/ai-suite/traefik}"
readonly AI_SUITE_DIR="${AI_SUITE_DIR:-/opt/ai-suite}"

# ============================================
# FONCTIONS
# ============================================
log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

check_root() {
    [[ $EUID -eq 0 ]] || { error "Doit être exécuté en root"; exit 1; }
}

check_docker() {
    docker info &> /dev/null || { error "Docker n'est pas actif"; exit 1; }
}

get_public_ip() {
    curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

# ============================================
# ÉTAPE 1: SAISIE DE LA CONFIGURATION
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

    read -p "Nom de domaine (ex: hitech.tn): " DOMAIN
    DOMAIN="${DOMAIN:-hitech.tn}"

    read -p "Email pour Let's Encrypt (ex: admin@${DOMAIN}): " SSL_EMAIL
    SSL_EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"

    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Instructions DNS importantes                  ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Ajoutez ces enregistrements chez votre registrar :"
    echo ""
    echo -e "  ${BOLD}Type${NC}  ${BOLD}Nom${NC}               ${BOLD}Valeur${NC}"
    echo -e "  ───────────────────────────────────────────"
    echo -e "  ${CYAN}A${NC}     ${DOMAIN}          ${ip}"
    echo -e "  ${CYAN}A${NC}     *.${DOMAIN}        ${ip}"
    echo ""
    echo -e "⏳ Attendez la propagation DNS (quelques minutes à 48h)"
    echo ""

    read -p "Les enregistrements DNS sont-ils configurés ? (O/n): " dns_ok
    if [[ "$dns_ok" == "n" || "$dns_ok" == "N" ]]; then
        warn "Configurez d'abord les DNS, puis relancez ce script"
        exit 0
    fi

    # Vérification rapide
    local resolved
    resolved=$(dig +short "$DOMAIN" 2>/dev/null || host "$DOMAIN" 2>/dev/null | grep "has address" | awk '{print $NF}' || echo "")
    if [[ -n "$resolved" ]]; then
        success "DNS vérifié: $DOMAIN → $resolved"
    else
        warn "Impossible de vérifier le DNS (dig/host non installé ou propagation en cours)"
        warn "Continuez, mais vérifiez manuellement plus tard"
    fi
}

# ============================================
# ÉTAPE 2: PRÉPARATION
# ============================================
prepare_system() {
    log "Préparation du système..."

    # Créer le réseau ai-suite
    if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
        docker network create "$NETWORK_NAME"
        success "Réseau '$NETWORK_NAME' créé"
    else
        success "Réseau '$NETWORK_NAME' existe déjà"
    fi

    # Créer le dossier Traefik
    mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}

    # Libérer le port 80 si donbosco_nginx l'utilise
    if docker ps --format '{{.Names}}' | grep -q "donbosco_nginx"; then
        log "Reconfiguration de donbosco_nginx (port 80 → 8081)..."
        local nginx_network
        nginx_network=$(docker inspect donbosco_nginx --format '{{range $net := .NetworkSettings.Networks}}{{$net}}{{end}}' 2>/dev/null || echo "")
        docker stop donbosco_nginx
        # Démarrer sur un autre port
        docker rm donbosco_nginx
        local nginx_compose
        nginx_compose=$(docker inspect donbosco_nginx --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null || echo "/home/hitech/projects/Don-Bosco-Connect/don-bosco-connect/nginx/docker-compose.yml")
        if [[ -f "$nginx_compose" ]]; then
            # Modifier le docker-compose pour utiliser le port 8081
            sed -i 's/"80:80"/"8081:80"/g; s/80:80/8081:80/g' "$nginx_compose"
            cd "$(dirname "$nginx_compose")" && docker compose up -d 2>/dev/null || true
        fi
        success "donbosco_ginx reconfiguré sur le port 8081"
    fi

    # Ouvrir les ports firewall
    if command -v ufw &>/dev/null; then
        ufw allow 80/tcp 2>/dev/null || true
        ufw allow 443/tcp 2>/dev/null || true
        success "Ports 80/443 ouverts dans le pare-feu"
    fi
}

# ============================================
# ÉTAPE 3: DÉPLOIEMENT TRAEFIK
# ============================================
deploy_traefik() {
    log "Déploiement de Traefik avec le domaine $DOMAIN..."

    # Configuration principale Traefik
    cat > "$TRAEFIK_DIR/traefik.yml" << EOF
global:
  checkNewVersion: true
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: true

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
EOF

    # Règles dynamiques pour les services
    cat > "$TRAEFIK_DIR/config/dynamic-config.yml" << EOF
http:
  routers:
    code-server:
      rule: "Host(\`code.${DOMAIN}\`)"
      service: code-server
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    open-webui:
      rule: "Host(\`chat.${DOMAIN}\`)"
      service: open-webui
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    ollama:
      rule: "Host(\`ollama.${DOMAIN}\`)"
      service: ollama
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    coolify:
      rule: "Host(\`coolify.${DOMAIN}\`)"
      service: coolify
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

EOF

    # Vérifier et ajouter donbosco si présent
    if docker ps --format '{{.Names}}' | grep -q "donbosco"; then
        local nginx_ip
        nginx_ip=$(docker inspect donbosco_nginx --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$conf.IPAddress}}{{"\n"}}{{end}}' 2>/dev/null | head -1)
        if [[ -n "$nginx_ip" ]]; then
            cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << EOF
    donbosco:
      rule: "Host(\`donbosco.${DOMAIN}\`)"
      service: donbosco
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

EOF
        fi
    fi

    # Services
    cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << EOF
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

EOF

    if [[ -n "${nginx_ip:-}" ]]; then
        cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << EOF
    donbosco:
      loadBalancer:
        servers:
          - url: "http://${nginx_ip}:80"

EOF
    fi

    cat >> "$TRAEFIK_DIR/config/dynamic-config.yml" << EOF
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
EOF

    # Docker Compose Traefik
    cat > "$TRAEFIK_DIR/docker-compose.yml" << EOF
version: '3.8'
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
      - TZ=Africa/Tunis
    labels:
      - "traefik.enable=true"

networks:
  ${NETWORK_NAME}:
    external: true
EOF

    success "Configuration Traefik générée"
}

# ============================================
# ÉTAPE 4: METTRE À JOUR LES SERVICES
# ============================================
update_services() {
    log "Mise à jour des services AI Suite avec le domaine $DOMAIN..."

    # Code-Server
    if [[ -f "$AI_SUITE_DIR/code-server/docker-compose.yml" ]]; then
        cat > "$AI_SUITE_DIR/code-server/docker-compose.yml" << EOF
version: '3.8'
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-server
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Africa/Tunis
      - PASSWORD=${CODE_SERVER_PASSWORD:-$(openssl rand -base64 24)}
      - SUDO_PASSWORD=${CODE_SERVER_PASSWORD:-changeme_now}
      - DEFAULT_WORKSPACE=/config/workspace
    volumes:
      - ./config:/config
      - ./projects:/projects
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    mem_limit: 2g
    mem_reservation: 512m
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.code-server.rule=Host(\`code.${DOMAIN}\`)"
      - "traefik.http.routers.code-server.tls=true"
      - "traefik.http.services.code-server.loadbalancer.server.url=http://code-server:8443"
networks:
  ${NETWORK_NAME}:
    external: true
EOF
        success "Code-Server configuré pour code.${DOMAIN}"
    fi

    # Ollama
    if [[ -f "$AI_SUITE_DIR/ollama/docker-compose.yml" ]]; then
        cat > "$AI_SUITE_DIR/ollama/docker-compose.yml" << EOF
version: '3.8'
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    volumes:
      - ollama:/root/.ollama
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    environment:
      - OLLAMA_HOST=0.0.0.0
    deploy:
      resources:
        limits:
          memory: 8g
        reservations:
          memory: 4g
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ollama.rule=Host(\`ollama.${DOMAIN}\`)"
      - "traefik.http.routers.ollama.tls=true"
networks:
  ${NETWORK_NAME}:
    external: true
volumes:
  ollama:
    driver: local
EOF
        success "Ollama configuré pour ollama.${DOMAIN}"
    fi

    # Open WebUI
    if [[ -f "$AI_SUITE_DIR/open-webui/docker-compose.yml" ]]; then
        cat > "$AI_SUITE_DIR/open-webui/docker-compose.yml" << EOF
version: '3.8'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET:-$(openssl rand -hex 32)}
      - ENABLE_SIGNUP=false
      - ENABLE_COMMUNITY_SHARING=false
    volumes:
      - open-webui:/app/backend/data
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    depends_on:
      - ollama
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.open-webui.rule=Host(\`chat.${DOMAIN}\`)"
      - "traefik.http.routers.open-webui.tls=true"
      - "traefik.http.services.open-webui.loadbalancer.server.url=http://open-webui:8080"
networks:
  ${NETWORK_NAME}:
    external: true
volumes:
  open-webui:
    driver: local
EOF
        success "Open WebUI configuré pour chat.${DOMAIN}"
    fi
}

# ============================================
# ÉTAPE 5: CONNECTER LES SERVICES EXISTANTS
# ============================================
connect_existing_services() {
    log "Connexion des services existants au réseau ${NETWORK_NAME}..."

    # Connecter Coolify au réseau ai-suite
    if docker ps --format '{{.Names}}' | grep -q "^coolify$"; then
        docker network connect "$NETWORK_NAME" coolify 2>/dev/null && \
            success "Coolify connecté au réseau ${NETWORK_NAME}" || \
            warn "Coolify déjà connecté ou erreur"
    fi

    # Connecter donbosco_nginx au réseau ai-suite
    if docker ps --format '{{.Names}}' | grep -q "donbosco_nginx"; then
        docker network connect "$NETWORK_NAME" donbosco_nginx 2>/dev/null && \
            success "donbosco_nginx connecté au réseau ${NETWORK_NAME}" || \
            warn "donbosco_nginx déjà connecté ou erreur"
    fi

    # Connecter donbosco_api si présent
    if docker ps --format '{{.Names}}' | grep -q "donbosco_api"; then
        docker network connect "$NETWORK_NAME" donbosco_api 2>/dev/null || true
    fi
}

# ============================================
# ÉTAPE 6: DÉMARRER LES SERVICES
# ============================================
start_services() {
    log "Démarrage des services..."

    # Démarrer Traefik
    cd "$TRAEFIK_DIR" && docker compose up -d
    success "Traefik démarré"

    # Démarrer les services AI Suite
    for service_dir in "$AI_SUITE_DIR"/code-server "$AI_SUITE_DIR"/ollama "$AI_SUITE_DIR"/open-webui; do
        if [[ -f "$service_dir/docker-compose.yml" ]]; then
            cd "$service_dir" && docker compose up -d 2>/dev/null || \
                warn "Impossible de démarrer $(basename "$service_dir")"
        fi
    done

    success "Tous les services démarrés"
}

# ============================================
# ÉTAPE 7: RENOUVELLEMENT SSL
# ============================================
setup_ssl_renewal() {
    log "Configuration du renouvellement SSL..."

    cat > "$TRAEFIK_DIR/renew-ssl.sh" << 'EOF'
#!/bin/bash
docker exec traefik traefik certificates rotate
echo "$(date): Certificats renouvelés" >> /var/log/ssl-renewal.log
EOF
    chmod +x "$TRAEFIK_DIR/renew-ssl.sh"

    (crontab -l 2>/dev/null | grep -v "renew-ssl"
     echo "0 3 * * * $TRAEFIK_DIR/renew-ssl.sh >> /var/log/ssl-renewal.log 2>&1") | crontab -

    success "Renouvellement SSL configuré (cron: 3h tous les jours)"
}

# ============================================
# ÉTAPE 8: EXPORTER LA CONFIG
# ============================================
export_config() {
    cat > "$SCRIPT_DIR/.env" << EOF
DOMAIN=${DOMAIN}
SSL_EMAIL=${SSL_EMAIL}
OLLAMA_PORT=${OLLAMA_PORT:-11434}
CODE_SERVER_PORT=${CODE_SERVER_PORT:-8443}
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT:-3000}
COOLIFY_PORT=${COOLIFY_PORT:-8000}
CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD:-}
WEBUI_SECRET=${WEBUI_SECRET:-}
TRAEFIK_HTTP_PORT=80
TRAEFIK_HTTPS_PORT=443
NETWORK_NAME=${NETWORK_NAME}
AI_SUITE_DIR=${AI_SUITE_DIR}
EOF
    chmod 600 "$SCRIPT_DIR/.env"
    success "Configuration exportée dans .env"
}

# ============================================
# RÉSUMÉ FINAL
# ============================================
show_summary() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Configuration du domaine terminée avec succès !${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}Accès aux services :${NC}"
    echo -e "  ────────────────────────────────────────────"
    echo -e "  ${CYAN}Coolify${NC}      https://coolify.${DOMAIN}"
    echo -e "  ${CYAN}Code-Server${NC}  https://code.${DOMAIN}"
    echo -e "  ${CYAN}Ollama API${NC}   https://ollama.${DOMAIN}"
    echo -e "  ${CYAN}Open WebUI${NC}   https://chat.${DOMAIN}"
    if docker ps --format '{{.Names}}' | grep -q "donbosco"; then
        echo -e "  ${CYAN}Don Bosco${NC}    https://donbosco.${DOMAIN}"
    fi
    echo ""
    echo -e "${BOLD}Traefik Dashboard :${NC}"
    echo -e "  http://$(get_public_ip):8080"
    echo ""
    echo -e "${BOLD}${YELLOW}Prochaines étapes :${NC}"
    echo -e "  1. Patientez pour la génération des certificats SSL (Let's Encrypt)"
    echo -e "  2. Vérifiez: docker logs traefik | grep -i certificate"
    echo -e "  3. Ajoutez de nouveaux projets dans leurs sous-domaines:"
    echo -e "     https://monprojet.${DOMAIN}"
    echo ""
    echo -e "${BOLD}Nouveaux projets Docker :${NC}"
    echo -e "  Ajoutez ces labels à vos conteneurs:"
    echo -e "    - \"traefik.enable=true\""
    echo -e "    - \"traefik.http.routers.monservice.rule=Host(\`monservice.${DOMAIN}\`)\""
    echo -e "    - \"traefik.http.routers.monservice.tls=true\""
    echo -e "    - \"traefik.http.routers.monservice.entrypoints=websecure\""
    echo ""
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    check_root
    check_docker

    prompt_config
    prepare_system
    deploy_traefik
    update_services
    connect_existing_services
    start_services
    setup_ssl_renewal
    export_config
    show_summary
}

main "$@"
