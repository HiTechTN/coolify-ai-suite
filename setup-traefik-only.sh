#!/bin/bash
# setup-traefik-only.sh - Ajouter HTTPS/Traefik à une installation existante
# Author: Mohamed Azmi KAANICHE
# Version: 1.0

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
readonly NETWORK_NAME="ai-suite"
readonly TRAEFIK_DIR="/opt/ai-suite/traefik"
readonly HTTP_PORT="${HTTP_PORT:-80}"
readonly HTTPS_PORT="${HTTPS_PORT:-443}"

# ============================================
# FONCTIONS
# ============================================
log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

check_root() {
    [[ $EUID -eq 0 ]] || { error "Doit être exécuté en root"; exit 1; }
}

check_docker() {
    docker info &> /dev/null || { error "Docker n'est pas actif"; exit 1; }
}

# ============================================
# SCRIPT
# ============================================
main() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Ajout de Traefik/HTTPS à l'installation       ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    
    check_root
    check_docker
    
    # Créer le réseau si nécessaire
    log "Création du réseau Docker..."
    docker network create "$NETWORK_NAME" 2>/dev/null || true
    success "Réseau '$NETWORK_NAME' prêt"
    
    # Créer les dossiers
    mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}
    
    # Configuration Traefik
    log "Configuration de Traefik..."
    cat > "$TRAEFIK_DIR/traefik.yml" << 'EOF'
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
      email: admin@example.com
      storage: /acme/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: ai-suite
EOF
    success "traefik.yml créé"
    
    # Labels pour les services existants
    log "Ajout des labels Traefik aux services..."
    
    # Code-Server
    if [[ -f /opt/ai-suite/code-server/docker-compose.yml ]]; then
        if ! grep -q "traefik.enable" /opt/ai-suite/code-server/docker-compose.yml; then
            sed -i 's/labels:/labels:\n      - "traefik.enable=true"\n      - "traefik.http.routers.code-server.rule=Host(`code-server.local`)"\n      - "traefik.http.routers.code-server.tls=true"/' /opt/ai-suite/code-server/docker-compose.yml
            sed -i 's/networks:/# Add port for internal access\n    ports:\n      - "8443:8443"\n    networks:/' /opt/ai-suite/code-server/docker-compose.yml
            success "Code-Server configuré"
        fi
    fi
    
    # Ollama
    if [[ -f /opt/ai-suite/ollama/docker-compose.yml ]]; then
        if ! grep -q "traefik.enable" /opt/ai-suite/ollama/docker-compose.yml; then
            sed -i 's/labels:/labels:\n      - "traefik.enable=true"\n      - "traefik.http.routers.ollama.rule=Host(`ollama.local`)"\n      - "traefik.http.routers.ollama.tls=true"/' /opt/ai-suite/ollama/docker-compose.yml
            success "Ollama configuré"
        fi
    fi
    
    # Open WebUI
    if [[ -f /opt/ai-suite/open-webui/docker-compose.yml ]]; then
        if ! grep -q "traefik.enable" /opt/ai-suite/open-webui/docker-compose.yml; then
            sed -i 's/labels:/labels:\n      - "traefik.enable=true"\n      - "traefik.http.routers.open-webui.rule=Host(`openwebui.local`)"\n      - "traefik.http.routers.open-webui.tls=true"/' /opt/ai-suite/open-webui/docker-compose.yml
            success "Open WebUI configuré"
        fi
    fi
    
    # Docker Compose Traefik
    log "Création du docker-compose.yml Traefik..."
    cat > "$TRAEFIK_DIR/docker-compose.yml" << EOF
version: '3.8'
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
      - ./acme:/acme
      - ./traefik.yml:/traefik.yml
    networks:
      - $NETWORK_NAME
    restart: unless-stopped
    labels:
      - "traefik.enable=true"

networks:
  $NETWORK_NAME:
    external: true
EOF
    success "docker-compose.yml créé"
    
    # Ouvrir les ports
    log "Configuration du pare-feu..."
    ufw allow "$HTTP_PORT/tcp" 2>/dev/null || true
    ufw allow "$HTTPS_PORT/tcp" 2>/dev/null || true
    success "Ports ouverts"
    
    # Démarrer Traefik
    log "Démarrage de Traefik..."
    cd "$TRAEFIK_DIR" && docker compose up -d
    success "Traefik démarré"
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Traefik configuré avec succès !${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}Accès HTTPS :${NC}"
    echo -e "  • Modifiez /etc/hosts :"
    echo -e "    $(hostname -I | awk '{print $1}') code-server.local openwebui.local ollama.local"
    echo ""
    echo -e "${BOLD}Dashboard Traefik :${NC}"
    echo -e "  • http://$(hostname -I | awk '{print $1}'):8080"
    echo ""
    echo -e "${BOLD}Commandes :${NC}"
    echo -e "  • Redémarrer: cd $TRAEFIK_DIR && docker compose restart"
    echo -e "  • Logs: docker logs -f traefik"
    echo ""
}

main "$@"