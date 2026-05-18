#!/bin/bash
# setup-traefik-only.sh - Ajouter HTTPS/Traefik à une installation existante
# Author: Mohamed Azmi KAANICHE
# Version: 1.1
#
# Usage: sudo ./setup-traefik-only.sh
#   ou : sudo DOMAIN=hitech.tn SSL_EMAIL=admin@hitech.tn ./setup-traefik-only.sh

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
readonly NETWORK_NAME="${NETWORK_NAME:-ai-suite}"
readonly TRAEFIK_DIR="${TRAEFIK_DIR:-/opt/ai-suite/traefik}"
readonly HTTP_PORT="${HTTP_PORT:-80}"
readonly HTTPS_PORT="${HTTPS_PORT:-443}"
export DOMAIN="${DOMAIN:-}"
export SSL_EMAIL="${SSL_EMAIL:-admin@example.com}"

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

    # Charger .env si présent
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        set -a; source "$SCRIPT_DIR/.env"; set +a
    fi

    # Demander le domaine si non fourni
    if [[ -z "${DOMAIN:-}" ]]; then
        read -p "Nom de domaine (ex: hitech.tn, laisser vide pour .local): " input_domain
        DOMAIN="${input_domain:-}"
        if [[ -n "$DOMAIN" ]]; then
            read -p "Email Let's Encrypt (ex: admin@${DOMAIN}): " input_email
            SSL_EMAIL="${input_email:-admin@${DOMAIN}}"
        fi
    fi

    check_root
    check_docker

    local tld="${DOMAIN:-local}"

    # Créer le réseau si nécessaire
    log "Création du réseau Docker..."
    docker network create "$NETWORK_NAME" 2>/dev/null || true
    success "Réseau '$NETWORK_NAME' prêt"

    # Créer les dossiers
    mkdir -p "$TRAEFIK_DIR"/{config,acme,logs}

    # Configuration Traefik
    log "Configuration de Traefik..."
    cat > "$TRAEFIK_DIR/traefik.yml" << EOF
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
EOF
    success "traefik.yml créé"

    # Config dynamique si domaine fourni
    if [[ -n "$DOMAIN" ]]; then
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
        success "Config dynamique créée pour le domaine $DOMAIN"
    fi

    # Labels pour les services existants
    log "Ajout des labels Traefik aux services..."

    add_traefik_labels() {
        local compose_file="$1"
        local service_name="$2"
        local hostname="$3"

        if [[ ! -f "$compose_file" ]]; then
            return
        fi

        if grep -q "traefik.enable" "$compose_file"; then
            return
        fi

        local labels_block
        labels_block=$(printf '      - "traefik.enable=true"\n      - "traefik.http.routers.%s.rule=Host(\\\`%s.%s\\\`)"\n      - "traefik.http.routers.%s.tls=true"' \
            "$service_name" "$hostname" "$tld" "$service_name")

        sed -i "/^labels:/a\\$labels_block" "$compose_file"
        success "$service_name configuré"
    }

    add_traefik_labels "/opt/ai-suite/code-server/docker-compose.yml" "code-server" "code"
    add_traefik_labels "/opt/ai-suite/ollama/docker-compose.yml" "ollama" "ollama"
    add_traefik_labels "/opt/ai-suite/open-webui/docker-compose.yml" "open-webui" "chat"

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
      - ./config:/config
      - ./acme:/acme
      - ./traefik.yml:/traefik.yml
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

    # Exporter la config
    if [[ -n "$DOMAIN" ]]; then
        cat > "$SCRIPT_DIR/.env" << EOF
DOMAIN=${DOMAIN}
SSL_EMAIL=${SSL_EMAIL}
NETWORK_NAME=${NETWORK_NAME}
EOF
        chmod 600 "$SCRIPT_DIR/.env" 2>/dev/null || true
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Traefik configuré avec succès !${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo ""
    if [[ -n "$DOMAIN" ]]; then
        echo -e "${BOLD}Accès HTTPS (SSL automatique) :${NC}"
        echo -e "  • Code-Server: https://code.${DOMAIN}"
        echo -e "  • Open WebUI:  https://chat.${DOMAIN}"
        echo -e "  • Ollama API:  https://ollama.${DOMAIN}"
        echo ""
        echo -e "${BOLD}Configuration DNS requise :${NC}"
        echo -e "  A      ${DOMAIN}    → $(hostname -I | awk '{print $1}')"
        echo -e "  A      *.${DOMAIN}  → $(hostname -I | awk '{print $1}')"
        echo ""
    else
        echo -e "${BOLD}Accès HTTPS (mode développement) :${NC}"
        echo -e "  • Modifiez /etc/hosts :"
        echo -e "    $(hostname -I | awk '{print $1}') code-server.local chat.local ollama.local"
        echo ""
    fi
    echo -e "${BOLD}Dashboard Traefik :${NC}"
    echo -e "  • http://$(hostname -I | awk '{print $1}'):8080"
    echo ""
    echo -e "${BOLD}Commandes :${NC}"
    echo -e "  • Redémarrer: cd $TRAEFIK_DIR && docker compose restart"
    echo -e "  • Logs: docker logs -f traefik"
    echo ""
}

main "$@"
