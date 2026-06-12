#!/bin/bash
# check-ai-suite-status.sh - Vérifier l'état des services AI Suite
# Version: 3.0
#
# Usage: sudo ./check-ai-suite-status.sh [options]
# Options: -h, --help, --no-color

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

LOG_FILE="/var/log/ai-suite-status.log"

usage() {
    cat << EOF
${BOLD}NAME${NC}
    check-ai-suite-status.sh — Vérifier l'état des services

${BOLD}SYNOPSIS${NC}
    sudo ./check-ai-suite-status.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Affiche l'état des conteneurs, la santé des services et les
    ressources utilisées par la Coolify AI Suite.

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --no-color       Désactiver les couleurs
    --version        Afficher la version
EOF
}

usage_function=usage

parse_args() {
    local args=("$@")
    for arg in "${args[@]}"; do
        case "$arg" in
            -h|--help) usage; exit 0 ;;
            --version) echo "Coolify AI Suite v${AI_SUITE_VERSION}"; exit 0 ;;
            --no-color) NO_COLOR=true ;;
            *) log_error "Argument inconnu: ${arg}"; usage; exit 1 ;;
        esac
    done
}

check_service() {
    local name="$1"
    local port="$2"

    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/" 2>/dev/null | grep -qE "302|200"; then
        echo -e "  ${GREEN}✓${NC} ${name}: OK (port ${port})"
    elif curl -s -o /dev/null "http://localhost:${port}/" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${name}: OK (port ${port})"
    else
        echo -e "  ${YELLOW}⏳${NC} ${name}: En cours de démarrage... (port ${port})"
    fi
}

main() {
    parse_args "$@"

    local ip
    ip=$(get_local_ip)

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Coolify AI Suite v${AI_SUITE_VERSION} — État des services  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Containers
    echo -e "${CYAN}📦 Containers Docker :${NC}"
    echo -e "────────────────────────────────────────────"
    docker ps -a --filter "name=code-server" --filter "name=ollama" --filter "name=open-webui" --filter "name=traefik" --filter "name=coolify" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "  Aucun container trouvé"
    echo ""

    # URLs
    echo -e "${CYAN}🌐 URLs d'accès :${NC}"
    echo -e "────────────────────────────────────────────"
    echo -e "  • Coolify:     ${BLUE}http://${ip}:${COOLIFY_PORT:-8000}${NC}"
    echo -e "  • Code-Server: ${BLUE}http://${ip}:${CODE_SERVER_PORT:-8443}${NC}"
    echo -e "  • Open WebUI:  ${BLUE}http://${ip}:${OPEN_WEBUI_PORT:-3000}${NC}"
    echo -e "  • Ollama API:  ${BLUE}http://${ip}:${OLLAMA_PORT:-11434}${NC}"
    echo -e "  • Traefik:     ${BLUE}http://${ip}:8080${NC}"
    echo ""

    # Santé
    echo -e "${CYAN}💚 Santé des services :${NC}"
    echo -e "────────────────────────────────────────────"
    check_service "Code-Server" "${CODE_SERVER_PORT:-8443}"
    check_service "Open WebUI" "${OPEN_WEBUI_PORT:-3000}"

    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Ollama: OK (${OLLAMA_PORT:-11434})"
        echo -e "     ${CYAN}Modèles installés:${NC}"
        curl -s http://localhost:11434/api/tags | jq -r '.models[] | "       • " + .name' 2>/dev/null || echo "       (aucun)"
    else
        echo -e "  ${YELLOW}⏳${NC} Ollama: En cours de démarrage..."
    fi

    if docker_service_running "traefik"; then
        echo -e "  ${GREEN}✓${NC} Traefik: OK (proxy HTTPS actif)"
    else
        echo -e "  ${YELLOW}⏳${NC} Traefik: Non configuré"
    fi
    echo ""

    # Ressources
    echo -e "${CYAN}💾 Ressources Docker :${NC}"
    echo -e "────────────────────────────────────────────"
    docker system df --format "table {{.Type}}\t{{.Total}}\t{{.Size}}\t{{.Active}}" 2>/dev/null || docker system df
    echo ""

    # Réseau
    echo -e "${CYAN}🔗 Réseau '${NETWORK_NAME}' :${NC}"
    if docker network inspect "$NETWORK_NAME" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Réseau présent"
        local containers
        containers=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
        if [[ -n "$containers" ]]; then
            echo -e "     Conteneurs connectés: ${containers}"
        fi
    else
        echo -e "  ${RED}✗${NC} Non configuré"
    fi
    echo ""

    # Traefik SSL
    if docker_service_running "traefik"; then
        echo -e "${CYAN}🔒 Certificats SSL :${NC}"
        echo -e "────────────────────────────────────────────"
        docker logs traefik 2>&1 | grep -i "certificate\|acme" | tail -5 || echo "  (aucun log SSL récent)"
        echo ""
    fi

    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "Dernière vérification: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

main "$@"
