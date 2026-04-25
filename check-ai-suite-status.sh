#!/bin/bash
# check-ai-suite-status.sh - Vérifier l'état des services AI Suite
# Version: 2.0

set -euo pipefail

# ============================================
# COULEURS
# ============================================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# FONCTIONS
# ============================================
get_ip() {
    hostname -I | awk '{print $1}'
}

check_service() {
    local name="$1"
    local url="$2"
    local port="$3"
    
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/" | grep -qE "302|200"; then
        echo -e "  ${GREEN}✓${NC} $name: OK"
        return 0
    else
        echo -e "  ${YELLOW}⏳${NC} $name: En cours de démarrage..."
        return 1
    fi
}

# ============================================
# EN-TÊTE
# ============================================
IP=$(get_ip)

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Coolify AI Suite - État des services        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# CONTAINERS
# ============================================
echo -e "${CYAN}📦 Containers Docker :${NC}"
echo -e "────────────────────────────────────────────"
docker ps -a --filter "name=code-server" --filter "name=ollama" --filter "name=open-webui" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Aucun container trouvé"
echo ""

# ============================================
# URLS
# ============================================
echo -e "${CYAN}🌐 URLs d'accès :${NC}"
echo -e "────────────────────────────────────────────"
echo -e "  • Coolify:     ${BLUE}http://${IP}:8000${NC}"
echo -e "  • Code-Server: ${BLUE}http://${IP}:8443${NC}"
echo -e "  • Open WebUI:  ${BLUE}http://${IP}:3000${NC}"
echo -e "  • Ollama API:  ${BLUE}http://${IP}:11434${NC}"
echo ""

# ============================================
# SANTÉ DES SERVICES
# ============================================
echo -e "${CYAN}💚 Santé des services :${NC}"
echo -e "────────────────────────────────────────────"

check_service "Code-Server" "http://localhost:8443/" 8443
check_service "Open WebUI" "http://localhost:3000/" 3000

# Ollama (avec modèles)
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Ollama: OK"
    echo -e "     ${CYAN}Modèles installés:${NC}"
    curl -s http://localhost:11434/api/tags | jq -r '.models[] | "       • " + .name' 2>/dev/null || echo "       (aucun)"
else
    echo -e "  ${YELLOW}⏳${NC} Ollama: En cours de démarrage..."
fi
echo ""

# ============================================
# RESSOURCES
# ============================================
echo -e "${CYAN}💾 Ressources Docker :${NC}"
echo -e "────────────────────────────────────────────"
docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Size}}\t{{.Active}}" 2>/dev/null || docker system df
echo ""

# ============================================
# RÉSEAU
# ============================================
if docker network inspect ai-suite &> /dev/null; then
    echo -e "${CYAN}🔗 Réseau 'ai-suite' :${NC}"
    echo -e "  ${GREEN}✓${NC} Réseauprésent"
else
    echo -e "${CYAN}🔗 Réseau 'ai-suite' :${NC}"
    echo -e "  ${RED}✗${NC} Non configuré"
fi
echo ""

# ============================================
# PIED DE PAGE
# ============================================
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "Dernier vérification: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""