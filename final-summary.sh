#!/bin/bash
# final-summary.sh - Résumé final de l'installation Coolify AI Suite
# Version: 2.1

set -euo pipefail

# ============================================
# COULEURS
# ============================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================
# CONFIGURATION
# ============================================
readonly IP=$(hostname -I | awk '{print $1}')
readonly OLLAMA_PORT="${OLLAMA_PORT:-11434}"
readonly CODE_SERVER_PORT="${CODE_SERVER_PORT:-8443}"
readonly OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"
readonly COOLIFY_PORT="${COOLIFY_PORT:-8000}"
DOMAIN="${DOMAIN:-}"

# Charger .env si présent
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

# ============================================
# FONCTIONS
# ============================================
check_service() {
    local name="$1"
    local port="$2"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/" 2>/dev/null || echo "000")

    if echo "$status" | grep -qE "200|302"; then
        echo -e "  ${GREEN}✓${NC} $name: http://${IP}:${port}"
        return 0
    else
        echo -e "  ${YELLOW}⏳${NC} $name: Hors ligne"
        return 1
    fi
}

check_ollama() {
    if curl -s "http://localhost:${OLLAMA_PORT}/api/tags" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Ollama: http://${IP}:${OLLAMA_PORT}"
        echo -e "     ${CYAN}Modèles:${NC}"
        curl -s "http://localhost:${OLLAMA_PORT}/api/tags" | jq -r '.models[].name' 2>/dev/null | while read model; do
            echo -e "       • $model"
        done
        return 0
    else
        echo -e "  ${YELLOW}⏳${NC} Ollama: En cours de démarrage..."
        return 1
    fi
}

# ============================================
# EN-TÊTE
# ============================================
clear
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         ✅ COOLIFY AI SUITE - INSTALLATION TERMINÉE      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# ÉTAT DES SERVICES
# ============================================
echo -e "${BOLD}${CYAN}📊 ÉTAT DES SERVICES :${NC}"
echo -e "────────────────────────────────────────────────────────"
check_service "Coolify" "$COOLIFY_PORT"
check_service "Code-Server" "$CODE_SERVER_PORT"
check_ollama
check_service "Open WebUI" "$OPEN_WEBUI_PORT"
echo ""

# ============================================
# URLs
# ============================================
if [[ -n "${DOMAIN:-}" ]]; then
    echo -e "${BOLD}${CYAN}🌐 ACCÈS PAR DOMAINE :${NC}"
    echo -e "────────────────────────────────────────────────────────"
    echo -e "  https://coolify.${DOMAIN}"
    echo -e "  https://code.${DOMAIN}"
    echo -e "  https://chat.${DOMAIN}"
    echo -e "  https://ollama.${DOMAIN}"
    echo ""
fi

# ============================================
# DOSSIERS
# ============================================
echo -e "${BOLD}${CYAN}📁 DOSSIERS DE CONFIGURATION :${NC}"
echo -e "────────────────────────────────────────────────────────"
echo -e "  /opt/ai-suite/code-server/  - Code-Server"
echo -e "  /opt/ai-suite/ollama/      - Ollama"
echo -e "  /opt/ai-suite/open-webui/ - Open WebUI"
echo ""

# ============================================
# SCRIPTS
# ============================================
echo -e "${BOLD}${CYAN}🛠️  SCRIPTS UTILES :${NC}"
echo -e "────────────────────────────────────────────────────────"
echo -e "  check-ai-suite-status.sh  - Vérifier l'état des services"
echo -e "  install-ollama-models.sh  - Installer les modèles IA"
echo -e "  backup-ai-suite.sh       - Sauvegarde / restauration"
echo -e "  setup-domain.sh          - Configurer un nom de domaine"
echo -e "  README.md                - Documentation complète"
echo ""

# ============================================
# COMMANDES RAPIDES
# ============================================
echo -e "${BOLD}${CYAN}📝 COMMANDES RAPIDES :${NC}"
echo -e "────────────────────────────────────────────────────────"
echo -e "  # Voir les logs"
echo -e "  sudo docker logs -f <service-name>"
echo ""
echo -e "  # Redémarrer un service"
echo -e "  cd /opt/ai-suite/<service> && sudo docker compose restart"
echo ""
echo -e "  # Installer un modèle"
echo -e "  sudo docker exec ollama ollama pull llama3.2:3b"
echo ""

# ============================================
# SÉCURITÉ
# ============================================
echo -e "${BOLD}${CYAN}🔒 SÉCURITÉ :${NC}"
echo -e "────────────────────────────────────────────────────────"
echo -e "  ${GREEN}✓${NC} Pare-feu (UFW) configuré"
echo -e "  ${GREEN}✓${NC} Fail2Ban actif"
echo -e "  ${YELLOW}⚠${NC} Changez les mots de passe par défaut"
echo -e "  ${YELLOW}⚠${NC} Sauvegardez /data/coolify/source/.env"
echo ""

# ============================================
# CONSEIL FINAL
# ============================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "  💡 Commencez par accéder à Code-Server et activez"
echo -e "     l'assistance IA via Open WebUI !"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
