#!/bin/bash
# setup-ai-suite.sh - Installation complète de Coolify AI Suite avec HTTPS
# Author: Mohamed Azmi KAANICHE
# Version: 3.0
#
# Usage: sudo ./setup-ai-suite.sh [options]
#
# Options:
#   -h, --help       Afficher cette aide
#   --dry-run        Simuler l'installation sans rien modifier
#   --force          Ignorer les vérifications préalables
#   --no-color       Désactiver les couleurs
#   --log FILE       Écrire les logs dans un fichier
#   --unattended     Installation non-interactive (utilise .env si présent)
#   --version        Afficher la version

set -euo pipefail

# ============================================
# SOURCE DES BIBLIOTHÈQUES
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

# ============================================
# CONFIGURATION SPÉCIFIQUE
# ============================================
LOG_FILE="/var/log/ai-suite-install.log"
UNATTENDED=false

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    setup-ai-suite.sh — Installation complète de Coolify AI Suite

${BOLD}SYNOPSIS${NC}
    sudo ./setup-ai-suite.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Déploie une stack IA auto-hébergée complète : Coolify, Code-Server,
    Ollama, Open WebUI et Traefik (HTTPS).

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --dry-run        Simuler l'installation sans rien modifier
    --force          Ignorer les vérifications préalables
    --no-color       Désactiver les couleurs
    --unattended     Mode non-interactif (utilise les variables d'environnement)
    --enable-gpu     Activer le support GPU NVIDIA pour Ollama
    --log FILE       Écrire les logs dans un fichier
    --version        Afficher la version

${BOLD}VARIABLES D'ENVIRONNEMENT${NC}
    DOMAIN               Nom de domaine (ex: hitech.tn)
    SSL_EMAIL            Email pour Let's Encrypt
    COOLIFY_PORT         Port Coolify (défaut: 8000)
    CODE_SERVER_PORT     Port Code-Server (défaut: 8443)
    OLLAMA_PORT          Port Ollama (défaut: 11434)
    OPEN_WEBUI_PORT      Port Open WebUI (défaut: 3000)
    AI_SUITE_ENABLE_GPU  Activer le support GPU NVIDIA (true/false)

${BOLD}EXEMPLES${NC}
    sudo ./setup-ai-suite.sh
    sudo ./setup-ai-suite.sh --dry-run
    sudo DOMAIN=hitech.tn ./setup-ai-suite.sh --unattended
EOF
}

usage_function=usage

# ============================================
# PARSE DES ARGUMENTS
# ============================================
parse_args() {
    local args=("$@")
    local remaining=()

    for arg in "${args[@]}"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --force) FORCE=true ;;
            --no-color) NO_COLOR=true ;;
            --unattended) UNATTENDED=true ;;
            --enable-gpu) export AI_SUITE_ENABLE_GPU=true ;;
            --version)
                echo "Coolify AI Suite v${AI_SUITE_VERSION}"
                exit 0
                ;;
            -h|--help)
                usage
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

    if [[ ${#remaining[@]} -gt 0 ]]; then
        log_error "Argument inconnu: ${remaining[0]}"
        usage
        exit 1
    fi
}

# ============================================
# VÉRIFICATIONS PRÉALABLES
# ============================================
check_requirements() {
    log_info "Vérification des prérequis système..."

    local total_mem=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $total_mem -lt 4096 ]]; then
        log_warning "RAM détectée: ${total_mem}MB (minimum recommandé: 4096MB)"
    else
        log_success "RAM: ${total_mem}MB"
    fi

    local avail_disk=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $avail_disk -lt 20 ]]; then
        log_warning "Espace disque disponible: ${avail_disk}GB (minimum recommandé: 20GB)"
    else
        log_success "Espace disque: ${avail_disk}GB"
    fi

    for port in "$TRAEFIK_HTTP_PORT" "$TRAEFIK_HTTPS_PORT" "$OLLAMA_PORT" "$CODE_SERVER_PORT" "$OPEN_WEBUI_PORT" "$COOLIFY_PORT"; do
        if ss -tuln 2>/dev/null | grep -q ":$port "; then
            if $FORCE; then
                log_warning "Le port $port est déjà occupé (forcé avec --force)"
            else
                log_error "Le port $port est déjà occupé (utilisez --force pour passer outre)"
                exit 1
            fi
        fi
    done
    log_success "Tous les ports sont disponibles"
}

check_docker_running() {
    if ! docker info &>/dev/null; then
        log_info "Docker n'est pas en cours d'exécution..."
        run_cmd "Démarrage de Docker" systemctl start docker
    fi
    log_success "Docker est actif"
}

# ============================================
# DÉTECTION DES SERVICES EXISTANTS
# ============================================
detect_existing_services() {
    local existing=()
    for service in coolify code-server ollama open-webui; do
        if docker_service_exists "$service"; then
            existing+=("$service")
        fi
    done
    echo "${existing[@]}"
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
    echo -e "${BOLD}${GREEN}Coolify AI Suite v${AI_SUITE_VERSION} — Script d'installation${NC}"
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

configure_custom() {
    show_banner
    echo -e "${BOLD}Configuration personnalisée${NC}"
    echo ""

    read -p "Nom de domaine (ex: hitech.tn, laisser vide pour .local): " input
    if [[ -n "$input" ]]; then
        export DOMAIN="$input"
        read -p "Email Let's Encrypt (ex: admin@${DOMAIN}): " email_input
        export SSL_EMAIL="${email_input:-admin@${DOMAIN}}"
    fi

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

select_services() {
    # Retour: lignes "services" puis "install_traefik" séparés par un —
    local services=()
    local install_traefik=false
    local choice

    while true; do
        show_menu
        echo -ne "${BOLD}Votre choix : ${NC}"
        read -r choice

        case "$choice" in
            1) services+=("coolify") ;;
            2) services+=("code-server") ;;
            3) services+=("ollama") ;;
            4) services+=("open-webui") ;;
            T|t) install_traefik=true ;;
            A|a)
                services=("coolify" "code-server" "ollama" "open-webui")
                install_traefik=true
                break
                ;;
            C|c)
                configure_custom
                echo "${services[*]}---${install_traefik}"
                return
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

    echo "${services[*]}---${install_traefik}"
}

# ============================================
# ÉTAPES D'INSTALLATION
# ============================================
install_requirements() {
    log_step "1" "8" "Installation des dépendances..."

    run_cmd "Mise à jour des paquets" apt-get update

    local packages=(curl wget git ufw fail2ban jq dnsutils)
    run_cmd "Installation des paquets système" apt-get install -y "${packages[@]}"

    if ! command -v docker &>/dev/null; then
        log_info "Installation de Docker..."
        run_cmd "Téléchargement du script Docker" \
            sh -c "curl -fsSL https://get.docker.com | sh"
        run_cmd "Activation de Docker au démarrage" systemctl enable docker
    fi

    log_success "Dépendances installées"
}

setup_security() {
    log_step "2" "8" "Configuration du pare-feu..."

    run_cmd_quiet "Activation de fail2ban" systemctl enable fail2ban

    if ufw status 2>/dev/null | grep -q "Status: inactive"; then
        run_cmd "Configuration UFW : deny incoming" ufw default deny incoming
        run_cmd "Configuration UFW : allow outgoing" ufw default allow outgoing
        run_cmd "UFW : allow SSH" ufw allow ssh
        run_cmd "UFW : allow HTTP" ufw allow "$TRAEFIK_HTTP_PORT/tcp"
        run_cmd "UFW : allow HTTPS" ufw allow "$TRAEFIK_HTTPS_PORT/tcp"
        run_cmd "UFW : allow Coolify" ufw allow "${COOLIFY_PORT}/tcp"
        run_cmd "UFW : allow Code-Server" ufw allow "${CODE_SERVER_PORT}/tcp"
        run_cmd "UFW : allow Ollama" ufw allow "${OLLAMA_PORT}/tcp"
        run_cmd "UFW : allow Open WebUI" ufw allow "${OPEN_WEBUI_PORT}/tcp"
        run_cmd "Activation de UFW" bash -c "echo 'y' | ufw enable"
    fi

    log_success "Sécurité configurée"
}

install_coolify() {
    log_step "3" "8" "Installation de Coolify..."

    if docker_service_exists "coolify"; then
        log_info "Coolify déjà installé, mise à jour..."
        run_cmd "Mise à jour Coolify" bash -c "curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash"
    else
        run_cmd "Installation Coolify" bash -c "curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash"
    fi

    log_success "Coolify installé/mis à jour"
}

create_network() {
    log_step "4" "8" "Création du réseau Docker..."

    if docker network inspect "$NETWORK_NAME" &>/dev/null; then
        log_info "Le réseau '$NETWORK_NAME' existe déjà"
    else
        run_cmd "Création du réseau '$NETWORK_NAME'" docker network create "$NETWORK_NAME"
    fi

    log_success "Réseau '$NETWORK_NAME' prêt"
}

setup_traefik() {
    log_step "5" "8" "Configuration de Traefik (HTTPS)..."

    mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}

    if docker_service_exists "traefik" && ! $FORCE; then
        log_info "Traefik déjà installé. Utilisez --force pour reconfigurer."
        log_success "Traefik déjà configuré"
        return
    fi

    # Configuration Traefik
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
    address: ":${TRAEFIK_HTTP_PORT}"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":${TRAEFIK_HTTPS_PORT}"

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
      rule: "Host(\`code.${TLD}\`)"
      service: code-server
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      middlewares:
        - secHeaders
        - rate-limit

    open-webui:
      rule: "Host(\`chat.${TLD}\`)"
      service: open-webui
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      middlewares:
        - secHeaders
        - rate-limit

    ollama:
      rule: "Host(\`ollama.${TLD}\`)"
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

    # Docker Compose Traefik
    cat > "$TRAEFIK_DIR/docker-compose.yml" << COMPOSE_EOF
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    command:
      - "--configfile=/traefik.yml"
    ports:
      - "${TRAEFIK_HTTP_PORT}:80"
      - "${TRAEFIK_HTTPS_PORT}:443"
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
      - "traefik.http.routers.api.rule=Host(\`traefik.${TLD}\`) || (Host(\`localhost\`) && PathPrefix(\`/api\`))"
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
    log_success "Traefik configuré et démarré"
}

install_nvidia_toolkit() {
    if ! detect_nvidia_runtime; then
        log_info "Installation du NVIDIA Container Toolkit..."
        run_cmd "Ajout du dépôt NVIDIA" \
            bash -c "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"

        run_cmd "Installation du toolkit" \
            bash -c "apt-get update -qq && apt-get install -y -qq nvidia-container-toolkit 2>/dev/null"

        run_cmd "Configuration du runtime Docker" \
            bash -c "nvidia-ctk runtime configure --runtime=docker 2>/dev/null; systemctl restart docker"
        log_success "NVIDIA Container Toolkit installé"
    fi
}

setup_services() {
    log_step "6" "8" "Configuration des services..."

    local enable_gpu=false
    if ${AI_SUITE_ENABLE_GPU:-false}; then
        if detect_nvidia_gpu &>/dev/null; then
            enable_gpu=true
            log_info "GPU NVIDIA détecté — activation du support GPU pour Ollama"
            install_nvidia_toolkit
        else
            log_warning "Option GPU activée mais aucun GPU NVIDIA détecté"
        fi
    fi

    mkdir -p "$AI_SUITE_DIR"/{code-server,ollama,open-webui}

    # Code-Server
    cat > "$AI_SUITE_DIR/code-server/docker-compose.yml" << CODE_EOF
services:
  code-server:
    image: lscr.io/linuxserver/code-server:latest
    container_name: code-server
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TZ}
      - PASSWORD=${CODE_SERVER_PASSWORD:-$(generate_password)}
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
      - "traefik.http.routers.code-server.rule=Host(\`code.${TLD}\`)"
      - "traefik.http.routers.code-server.tls=true"
      - "traefik.http.services.code-server.loadbalancer.server.url=http://code-server:8443"
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8443/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
networks:
  ${NETWORK_NAME}:
    external: true
CODE_EOF

    # Ollama
    if $enable_gpu; then
        log_info "Génération du docker-compose Ollama avec support GPU"
        cat > "$AI_SUITE_DIR/ollama/docker-compose.yml" << OLLAMA_GPU_EOF
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
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ollama.rule=Host(\`ollama.${TLD}\`)"
      - "traefik.http.routers.ollama.tls=true"
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 6
      start_period: 60s
networks:
  ${NETWORK_NAME}:
    external: true
volumes:
  ollama:
    driver: local
OLLAMA_GPU_EOF
    else
        cat > "$AI_SUITE_DIR/ollama/docker-compose.yml" << OLLAMA_EOF
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
      - "traefik.http.routers.ollama.rule=Host(\`ollama.${TLD}\`)"
      - "traefik.http.routers.ollama.tls=true"
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 6
      start_period: 60s
networks:
  ${NETWORK_NAME}:
    external: true
volumes:
  ollama:
    driver: local
OLLAMA_EOF
    fi

    # Open WebUI
    cat > "$AI_SUITE_DIR/open-webui/docker-compose.yml" << WEBUI_EOF
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=${WEBUI_SECRET:-$(generate_secret)}
      - ENABLE_SIGNUP=false
      - ENABLE_COMMUNITY_SHARING=false
    volumes:
      - open-webui:/app/backend/data
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    depends_on:
      - ollama
    mem_limit: 2g
    mem_reservation: 512m
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.open-webui.rule=Host(\`chat.${TLD}\`)"
      - "traefik.http.routers.open-webui.tls=true"
      - "traefik.http.services.open-webui.loadbalancer.server.url=http://open-webui:8080"
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
networks:
  ${NETWORK_NAME}:
    external: true
volumes:
  open-webui:
    driver: local
WEBUI_EOF

    # Démarrer chaque service
    for service_dir in "$AI_SUITE_DIR"/code-server "$AI_SUITE_DIR"/ollama "$AI_SUITE_DIR"/open-webui; do
        local name
        name=$(basename "$service_dir")
        if [[ -f "$service_dir/docker-compose.yml" ]]; then
            run_cmd "Démarrage de ${name}" bash -c "cd '${service_dir}' && docker compose up -d"
        fi
    done

    log_success "Services configurés et démarrés"
}

setup_cleanup() {
    log_step "7" "8" "Configuration du nettoyage automatique..."

    cat > "$AI_SUITE_DIR/cleanup.sh" << 'CLEANUP_EOF'
#!/bin/bash
# Nettoyage automatique Docker
docker system prune -af --filter "until=168h" --force
docker volume prune -f
echo "$(date): Nettoyage exécuté" >> /var/log/ai-cleanup.log
CLEANUP_EOF
    chmod +x "$AI_SUITE_DIR/cleanup.sh"

    if ! crontab -l 2>/dev/null | grep -q "cleanup.sh"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * $AI_SUITE_DIR/cleanup.sh >> /var/log/ai-cleanup.log 2>&1") | crontab -
        log_success "Cron de nettoyage ajouté"
    else
        log_info "Cron de nettoyage déjà présent"
    fi

    log_success "Nettoyage automatique configuré"
}

setup_watchtower() {
    log_step "8" "9" "Configuration de Watchtower (mises à jour automatiques)..."

    local watchtower_dir="${AI_SUITE_DIR}/watchtower"

    if docker_service_exists "watchtower"; then
        log_info "Watchtower déjà installé"
        return
    fi

    mkdir -p "$watchtower_dir"

    cat > "$watchtower_dir/docker-compose.yml" << WT_EOF
services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * *
      - WATCHTOWER_NOTIFICATIONS=log
      - WATCHTOWER_INCLUDE_RESTARTING=true
      - WATCHTOWER_TIMEOUT=30s
    labels:
      - "traefik.enable=false"
WT_EOF

    run_cmd "Démarrage de Watchtower" \
        bash -c "cd '${watchtower_dir}' && docker compose up -d"

    log_success "Watchtower configuré (mise à jour quotidienne à 4h00)"
}

setup_ssl_renewal() {
    log_step "9" "9" "Configuration du renouvellement SSL..."

    cat > "$TRAEFIK_DIR/renew-ssl.sh" << 'RENEW_EOF'
#!/bin/bash
docker exec traefik traefik certificates rotate
echo "$(date): Certificats renouvelés" >> /var/log/ssl-renewal.log
RENEW_EOF
    chmod +x "$TRAEFIK_DIR/renew-ssl.sh"

    if ! crontab -l 2>/dev/null | grep -q "renew-ssl"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * $TRAEFIK_DIR/renew-ssl.sh >> /var/log/ssl-renewal.log 2>&1") | crontab -
        log_success "Cron de renouvellement SSL ajouté"
    else
        log_info "Cron SSL déjà présent"
    fi

    log_success "Renouvellement SSL configuré"
}

# ============================================
# EXPORT DE LA CONFIGURATION
# ============================================
export_config() {
    cat > "$SCRIPT_DIR/.env" << ENV_EOF
# Coolify AI Suite - Configuration générée
# Version: ${AI_SUITE_VERSION}
DOMAIN=${DOMAIN:-}
SSL_EMAIL=${SSL_EMAIL:-admin@example.com}
OLLAMA_PORT=${OLLAMA_PORT}
CODE_SERVER_PORT=${CODE_SERVER_PORT}
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT}
COOLIFY_PORT=${COOLIFY_PORT}
CODE_SERVER_PASSWORD=${CODE_SERVER_PASSWORD:-}
WEBUI_SECRET=${WEBUI_SECRET:-}
TRAEFIK_HTTP_PORT=${TRAEFIK_HTTP_PORT:-80}
TRAEFIK_HTTPS_PORT=${TRAEFIK_HTTPS_PORT:-443}
NETWORK_NAME=${NETWORK_NAME}
AI_SUITE_DIR=${AI_SUITE_DIR}
BACKUP_DIR=${BACKUP_DIR}
RETENTION_DAYS=${RETENTION_DAYS}
TZ=${TZ}
ENV_EOF
    chmod 600 "$SCRIPT_DIR/.env"
    log_success "Configuration exportée dans .env"
}

# ============================================
# RÉSUMÉ FINAL
# ============================================
show_summary() {
    local ip
    ip=$(get_local_ip)

    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}✓ Installation terminée avec succès !${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""

    if [[ -n "${DOMAIN:-}" ]]; then
        echo -e "${BOLD}URLs (HTTPS automatique Let's Encrypt) :${NC}"
        echo -e "  • Coolify:      https://coolify.${DOMAIN}"
        echo -e "  • Code-Server:  https://code.${DOMAIN}"
        echo -e "  • Open WebUI:   https://chat.${DOMAIN}"
        echo -e "  • Ollama API:   https://ollama.${DOMAIN}"
        echo ""
        echo -e "${BOLD}Dashboard Traefik :${NC} http://${ip}:8080"
        echo ""
        echo -e "${BOLD}${YELLOW}Configuration DNS requise :${NC}"
        echo -e "  A      ${DOMAIN}        → ${ip}"
        echo -e "  A      *.${DOMAIN}      → ${ip}"
    else
        echo -e "${BOLD}URLs HTTP :${NC}"
        echo -e "  • Coolify:      http://${ip}:${COOLIFY_PORT}"
        echo -e "  • Code-Server: http://${ip}:${CODE_SERVER_PORT}"
        echo -e "  • Open WebUI:  http://${ip}:${OPEN_WEBUI_PORT}"
        echo -e "  • Ollama API:  http://${ip}:${OLLAMA_PORT}"
        echo ""
        echo -e "${BOLD}URLs HTTPS :${NC}"
        echo -e "  • http://${ip} (redirection vers HTTPS)"
        echo -e "  • Dashboard Traefik: http://${ip}:8080"
        echo ""
        echo -e "${BOLD}${YELLOW}Fichier hosts à modifier sur les clients :${NC}"
        echo -e "  ${ip} code-server.local openwebui.local ollama.local"
    fi

    echo ""
    echo -e "${BOLD}${YELLOW}Actions recommandées :${NC}"
    echo -e "  1. Modifiez /etc/hosts sur les machines clientes (mode .local)"
    echo -e "  2. Changez les mots de passe par défaut"
    echo -e "  3. Exécutez: ./install-ollama-models.sh"
    echo ""
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    setup_trap
    parse_args "$@"

    require_root

    # Charger .env si unattended
    if $UNATTENDED; then
        load_env
    fi

    export CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-$(generate_password)}"
    export WEBUI_SECRET="${WEBUI_SECRET:-$(generate_secret)}"

    check_docker_running
    check_requirements

    if $DRY_RUN; then
        log_warning "=== MODE DRY-RUN : aucune modification ne sera effectuée ==="
    fi

    if ! $UNATTENDED; then
        local result
        result=$(select_services)
        local services="${result%%---*}"
        local install_traefik="${result##*---}"

        if [[ -z "$services" ]]; then
            log_error "Aucun service sélectionné"
            exit 1
        fi

        log_info "Services sélectionnés : ${services}"
        if [[ "$install_traefik" == "true" ]]; then
            log_info "Traefik (HTTPS) sélectionné"
        fi
    fi

    export_config
    install_requirements
    setup_security
    install_coolify
    create_network
    setup_traefik
    setup_services
    setup_cleanup
    setup_watchtower
    setup_ssl_renewal
    show_summary
}

main "$@"
