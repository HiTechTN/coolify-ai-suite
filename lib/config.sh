#!/bin/bash
# lib/config.sh - Configuration centralisée pour Coolify AI Suite
# Version: 3.0
#
# Usage: source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/config.sh"

set -euo pipefail

# ============================================
# CHARGEMENT .env (si présent)
# ============================================
load_env

# ============================================
# PORTS — valeurs par défaut
# ============================================
export OLLAMA_PORT="${OLLAMA_PORT:-11434}"
export CODE_SERVER_PORT="${CODE_SERVER_PORT:-8443}"
export OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"
export COOLIFY_PORT="${COOLIFY_PORT:-8000}"
export TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-80}"
export TRAEFIK_HTTPS_PORT="${TRAEFIK_HTTPS_PORT:-443}"

# ============================================
# DOMAINE & SSL
# ============================================
export DOMAIN="${DOMAIN:-}"
export SSL_EMAIL="${SSL_EMAIL:-admin@example.com}"

# ============================================
# RÉSEAU
# ============================================
export NETWORK_NAME="${NETWORK_NAME:-ai-suite}"

# ============================================
# BACKUP
# ============================================
export BACKUP_DIR="${BACKUP_DIR:-/opt/backups/ai-suite}"
export RETENTION_DAYS="${RETENTION_DAYS:-7}"

# ============================================
# SURVEILLANCE IP
# ============================================
export FIXED_IP="${FIXED_IP:-}"
export DNS_SERVERS="${DNS_SERVERS:-}"

# ============================================
# FUSEAU HORAIRE
# ============================================
export TZ="${TZ:-Africa/Tunis}"

# ============================================
# MOTS DE PASSE (générés si vides, lus depuis .env)
# ============================================
CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-}"
WEBUI_SECRET="${WEBUI_SECRET:-}"

# ============================================
# VARIABLES DÉRIVÉES
# ============================================
export TLD="${DOMAIN:-local}"

get_domain_prefix() {
    if [[ -n "$DOMAIN" ]]; then
        return 0
    fi
    return 1
}
