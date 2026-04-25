#!/bin/bash
# setup-ai-suite.sh - Script d'installation Coolify AI Suite avec HTTPS
# Author: Mohamed Azmi KAANICHE
# Version: 2.1
# Date: 2026-04-25

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
# CONFIGURATION PAR DÉFAUT
# ============================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/ai-suite-install.log"
readonly OLLAMA_PORT="${OLLAMA_PORT:-11434}"
readonly CODE_SERVER_PORT="${CODE_SERVER_PORT:-8443}"
readonly OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"
readonly COOLIFY_PORT="${COOLIFY_PORT:-8000}"
readonly TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-80}"
readonly TRAEFIK_HTTPS_PORT="${TRAEFIK_HTTPS_PORT:-443}"
readonly NETWORK_NAME="ai-suite"
readonly AI_SUITE_DIR="/opt/ai-suite"
readonly TRAEFIK_DIR="/opt/ai-suite/traefik"

# ============================================
# FONCTIONS UTILITAIRES
# ============================================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg"
    echo "$msg" >> "$LOG_FILE"
}

log_step() {
    log "${BLUE}[$1/$2] ${NC}$3"
}

log_success() {
    log "${GREEN}✓ ${NC}$1"
}

log_error() {
    log "${RED}✗ ${NC}$1"
}

log_warning() {
    log "${YELLOW}⚠ ${NC}$1"
}

log_info() {
    log "${CYAN}ℹ ${NC}$1"
}

# ============================================
# VÉRIFICATIONS PRÉALABLES
# ============================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root"
        exit 1
    fi
}

check_dependencies() {
    local missing=()
    
    for cmd in curl docker; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dépendances manquantes: ${missing[*]}"
        log_info "Installation des dépendances..."
        apt-get update && apt-get install -y "${missing[@]}"
    fi
}

check_requirements() {
    log_info "Vérification des prérequis système..."
    
    local total_mem=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $total_mem -lt 4096 ]]; then
        log_warning "RAM détectée: ${total_mem}MB (minimum recommandé: 4096MB)"
    else
        log_success "RAM: ${total_mem}MB ✓"
    fi
    
    local avail_disk=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $avail_disk -lt 20 ]]; then
        log_warning "Espace disque disponible: ${avail_disk}GB (minimum recommandé: 20GB)"
    else
        log_success "Espace disque: ${avail_disk}GB ✓"
    fi
    
    for port in "$TRAEFIK_HTTP_PORT" "$TRAEFIK_HTTPS_PORT" "$OLLAMA_PORT" "$CODE_SERVER_PORT" "$OPEN_WEBUI_PORT" "$COOLIFY_PORT"; do
        if ss -tuln | grep -q ":$port "; then
            log_error "Le port $port est déjà occupé"
            exit 1
        fi
    done
    log_success "Tous les ports sont disponibles ✓"
}

check_docker() {
    if ! docker info &> /dev/null; then
        log_info "Docker n'est pas en cours d'exécution..."
        systemctl start docker || {
            log_error "Impossible de démarrer Docker"
            exit 1
        }
    fi
    log_success "Docker est actif ✓"
}

# ============================================
# MENU INTERACTIF
# ============================================
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
    ____            _ _    _         _    ____ _     ___
   / ___|___   ___ | | |  (_) __ _  / |  / ___| |   |_ _|
  | |   / _ \ / _ \| | |  | |/ _` | | | | |   | |    | |
  | |__| (_) | (_) | | |__| | (_| | | | | |___| |___ | |
   \____\___/ \___/|_|____|_|\__,_| |_|  \____|_____|___|

EOF
    echo -e "${NC}"
    echo -e "${BOLD}${GREEN}Coolify AI Suite - Script d'installation v2.1${NC}"
    echo -e "${YELLOW}=============================================${NC}"
    echo ""
}

show_menu() {
    show_banner
    echo -e "${BOLD}Services disponibles :${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Coolify         - Orchestrateur de déploiement"
    echo -e "  ${CYAN}[2]${NC} Code-Server    - IDE Visual Studio Code"
    echo -e "  ${CYAN}[3]${NC} Ollama         - Moteur de modèles LLM"
    echo -e "  ${CYAN}[4]${NC} Open WebUI     - Interface de chat IA"
    echo -e "  ${CYAN}[T]${NC} Traefik        - Proxy inverse + HTTPS (auto)"
    echo ""
    echo -e "  ${CYAN}[A]${NC} Tout installer"
    echo -e "  ${CYAN}[C]${NC} Configuration personnalisée"
    echo -e "  ${CYAN}[Q]${NC} Quitter"
    echo ""
}

select_services() {
    local services=()
    local choice
    local install_traefik=false
    
    while true; do
        show_menu
        echo -ne "${BOLD}Votre choix : ${NC}"
        read -r choice
        
        case "$choice" in
            1) services+=("coolify");;
            2) services+=("code-server");;
            3) services+=("ollama");;
            4) services+=("open-webui");;
            T|t) install_traefik=true;;
            A|a)
                services=("coolify" "code-server" "ollama" "open-webui")
                install_traefik=true
                break
                ;;
            C|c)
                configure_custom
                return "$install_traefik"
                ;;
            Q|q) exit 0 ;;
            *) log_error "Option invalide" ;;
        esac
        
        echo -e "\n${GREEN}Services sélectionnés : ${services[*]}${NC}"
        [[ "$install_traefik" == true ]] && echo -e "${GREEN}✓ Traefik (HTTPS) sélectionné${NC}"
        echo -ne "${BOLD}Continuer ? (O/n) : ${NC}"
        read -r confirm
        [[ "$confirm" != "n" && "$confirm" != "N" ]] && break
    done
    
    echo "$services" "$install_traefik"
}

configure_custom() {
    show_banner
    echo -e "${BOLD}Configuration personnalisée${NC}"
    echo ""
    
    read -p "Port Coolify (défaut: $COOLIFY_PORT): " input
    [[ -n "$input" ]] && export COOLIFY_PORT="$input"
    
    read -p "Port Code-Server (défaut: $CODE_SERVER_PORT): " input
    [[ -n "$input" ]] && export CODE_SERVER_PORT="$input"
    
    read -p "Port Ollama (défaut: $OLLAMA_PORT): " input
    [[ -n "$input" ]] && export OLLAMA_PORT="$input"
    
    read -p "Port Open WebUI (défaut: $OPEN_WEBUI_PORT): " input
    [[ -n "$input" ]] && export OPEN_WEBUI_PORT="$input"
    
    read -p "Installer Traefik avec HTTPS ? (O/n): " confirm
    [[ "$confirm" != "n" && "$confirm" != "N" ]]
}

# ============================================
# INSTALLATION
# ============================================
install_requirements() {
    log_step "1" "8" "Installation des dépendances..."
    
    apt-get update
    apt-get install -y curl wget git ufw fail2ban jq
    
    if ! command -v docker &> /dev/null; then
        log_info "Installation de Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
    fi
    
    log_success "Dépendances installées"
}

setup_security() {
    log_step "2" "8" "Configuration du pare-feu..."
    
    systemctl enable fail2ban 2>/dev/null || true
    
    if ufw status | grep -q "Status: inactive"; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow "$TRAEFIK_HTTP_PORT/tcp"
        ufw allow "$TRAEFIK_HTTPS_PORT/tcp"
        ufw allow "${COOLIFY_PORT}/tcp"
        ufw allow "${CODE_SERVER_PORT}/tcp"
        ufw allow "${OLLAMA_PORT}/tcp"
        ufw allow "${OPEN_WEBUI_PORT}/tcp"
        echo "y" | ufw enable
    fi
    
    log_success "Sécurité configurée"
}

install_coolify() {
    log_step "3" "8" "Installation de Coolify..."
    log_info "Exécution du script d'installation Coolify..."
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
    log_success "Coolify installé"
}

create_network() {
    log_step "4" "8" "Création du réseau Docker..."
    docker network create "$NETWORK_NAME" 2>/dev/null || true
    log_success "Réseau '$NETWORK_NAME' créé"
}

setup_traefik() {
    log_step "5" "8" "Configuration de Traefik (HTTPS)..."
    
    mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}
    
    # Configuration Traefik
    cat > "$TRAEFIK_DIR/traefik.yml" << 'EOF'
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
      email: admin@example.com
      storage: /acme/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: ai-suite
  file:
    directory: /config
    watch: true
EOF

    # Règles pour les services
    cat > "$TRAEFIK_DIR/config/dynamic-config.yml" << EOF
http:
  routers:
    code-server:
      rule: "Host(\`code-server.local\`)"
      service: code-server
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    open-webui:
      rule: "Host(\`openwebui.local\`)"
      service: open-webui
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

    ollama:
      rule: "Host(\`ollama.local\`)"
      service: ollama
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

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

tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
EOF

    # Docker Compose Traefik
    cat > "$TRAEFIK_DIR/docker-compose.yml" << 'EOF'
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
      - ai-suite
    restart: unless-stopped
    environment:
      - TZ=Europe/Paris
    labels:
      - "traefik.enable=true"

networks:
  ai-suite:
    external: true
EOF

    # Hooks pour les services (Labellés Traefik)
    log_info "Configuration des labels Traefik sur les services..."
    
    log_success "Traefik configuré"
}

setup_services() {
    log_step "6" "8" "Configuration des services..."
    
    mkdir -p "$AI_SUITE_DIR"/{code-server,ollama,open-webui}
    
    # Code-Server avec labels Traefik
    cat > "$AI_SUITE_DIR/code-server/docker-compose.yml" << EOF
version: '3.8'
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-server
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
      - PASSWORD=${CODE_SERVER_PASSWORD:-$(openssl rand -base64 24)}
      - SUDO_PASSWORD=${CODE_SERVER_PASSWORD:-changeme_now}
    volumes:
      - ./config:/config
      - ./projects:/projects
    networks:
      - ai-suite
    restart: unless-stopped
    mem_limit: 2g
    mem_reservation: 512m
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.code-server.rule=Host(\`code-server.local\`)"
      - "traefik.http.routers.code-server.tls=true"
      - "traefik.http.services.code-server.loadbalancer.server.url=http://code-server:8443"
networks:
  ai-suite:
    external: true
EOF

    # Ollama
    cat > "$AI_SUITE_DIR/ollama/docker-compose.yml" << EOF
version: '3.8'
services:
  ollama:
    image: ollama/ollama:pro
    container_name: ollama
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - ai-suite
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
      - "traefik.http.routers.ollama.rule=Host(\`ollama.local\`)"
      - "traefik.http.routers.ollama.tls=true"
networks:
  ai-suite:
    external: true
volumes:
  ollama-data:
    driver: local
EOF

    # Open WebUI avec labels Traefik
    cat > "$AI_SUITE_DIR/open-webui/docker-compose.yml" << EOF
version: '3.8'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET:-$(openssl rand -hex 32)}
    volumes:
      - open-webui-data:/app/backend/data
    networks:
      - ai-suite
    restart: unless-stopped
    depends_on:
      - ollama
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.open-webui.rule=Host(\`openwebui.local\`)"
      - "traefik.http.routers.open-webui.tls=true"
      - "traefik.http.services.open-webui.loadbalancer.server.url=http://open-webui:8080"
networks:
  ai-suite:
    external: true
volumes:
  open-webui-data:
    driver: local
EOF

    log_success "Services configurés"
}

setup_cleanup() {
    log_step "7" "8" "Configuration du nettoyage automatique..."
    
    cat > "$AI_SUITE_DIR/cleanup.sh" << 'EOF'
#!/bin/bash
docker system prune -af --filter "until=168h" --force
docker volume prune -f
EOF
    chmod +x "$AI_SUITE_DIR/cleanup.sh"
    
    (crontab -l 2>/dev/null | grep -v "ai-suite"; echo "0 2 * * * $AI_SUITE_DIR/cleanup.sh >> /var/log/ai-cleanup.log 2>&1") | crontab -
    
    log_success "Nettoyage automatique configuré"
}

setup_ssl_renewal() {
    log_step "8" "8" "Configuration du renouvellement SSL..."
    
    # Script de renouvellement
    cat > "$TRAEFIK_DIR/renew-ssl.sh" << 'EOF'
#!/bin/bash
# Renouvellement des certificats SSL Let's Encrypt
docker exec traefik traefik certificates rotate
echo "$(date): Certificats renouvelés" >> /var/log/ssl-renewal.log
EOF
    chmod +x "$TRAEFIK_DIR/renew-ssl.sh"
    
    # Cron pour renouveler 30 jours avant expiration
    (crontab -l 2>/dev/null | grep -v "renew-ssl"; echo "0 3 * * * $TRAEFIK_DIR/renew-ssl.sh >> /var/log/ssl-renewal.log 2>&1") | crontab -
    
    log_success "Renouvellement SSL configuré"
}

# ============================================
# EXPORTER LA CONFIG
# ============================================
export_config() {
    cat > "$SCRIPT_DIR/.env" << EOF
OLLAMA_PORT=$OLLAMA_PORT
CODE_SERVER_PORT=$CODE_SERVER_PORT
OPEN_WEBUI_PORT=$OPEN_WEBUI_PORT
COOLIFY_PORT=$COOLIFY_PORT
CODE_SERVER_PASSWORD=$CODE_SERVER_PASSWORD
WEBUI_SECRET=$WEBUI_SECRET
TRAEFIK_HTTP_PORT=$TRAEFIK_HTTP_PORT
TRAEFIK_HTTPS_PORT=$TRAEFIK_HTTPS_PORT
EOF
    chmod 600 "$SCRIPT_DIR/.env"
    log_success "Configuration exportée dans .env"
}

# ============================================
# RÉSUMÉ FINAL
# ============================================
show_summary() {
    local ip
    ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}✓ Installation terminée avec succès !${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "${BOLD}URLs HTTP (non sécurisé) :${NC}"
    echo -e "  • Coolify:      http://${ip}:${COOLIFY_PORT}"
    echo -e "  • Code-Server: http://${ip}:${CODE_SERVER_PORT}"
    echo -e "  • Open WebUI:  http://${ip}:${OPEN_WEBUI_PORT}"
    echo -e "  • Ollama API:  http://${ip}:${OLLAMA_PORT}"
    echo ""
    echo -e "${BOLD}URLs HTTPS (Traefik) :${NC}"
    echo -e "  • http://${ip} (redirection vers HTTPS)"
    echo -e "  • Dashboard Traefik: http://${ip}:8080"
    echo ""
    echo -e "${BOLD}${YELLOW}Fichier hosts à modifier sur les clients :${NC}"
    echo -e "  ${ip} code-server.local openwebui.local ollama.local"
    echo ""
    echo -e "${BOLD}${YELLOW}Actions recommandées :${NC}"
    echo -e "  1. Modifiez /etc/hosts sur les machines clientes"
    echo -e "  2. Changez les mots de passe par défaut"
    echo -e "  3. Exécutez: ~/Coolify\\ AI\\ Suite/install-ollama-models.sh"
    echo ""
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    export CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-$(openssl rand -base64 24)}"
    export WEBUI_SECRET="${WEBUI_SECRET:-$(openssl rand -hex 32)}"
    
    check_root
    check_dependencies
    check_docker
    check_requirements
    export_config
    
    install_requirements
    setup_security
    install_coolify
    create_network
    setup_traefik
    setup_services
    setup_cleanup
    setup_ssl_renewal
    show_summary
}

main "$@"