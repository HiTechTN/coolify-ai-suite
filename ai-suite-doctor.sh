#!/bin/bash
# ai-suite-doctor.sh - Diagnostic automatique de Coolify AI Suite
# Version: 1.0
#
# Usage: sudo ./ai-suite-doctor.sh [options]
#
# Options:
#   -h, --help       Afficher cette aide
#   --fix            Tenter de corriger les problèmes détectés
#   --no-color       Désactiver les couleurs
#   --version        Afficher la version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

LOG_FILE="/var/log/ai-suite-doctor.log"
FIX_MODE=false

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    ai-suite-doctor.sh — Diagnostic automatique de la AI Suite

${BOLD}SYNOPSIS${NC}
    sudo ./ai-suite-doctor.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Vérifie l'état de santé de tous les composants de la Coolify AI Suite
    et propose des corrections. Avec --fix, tente de corriger
    automatiquement les problèmes détectés.

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --fix            Tenter de corriger les problèmes détectés
    --no-color       Désactiver les couleurs
    --version        Afficher la version
EOF
}

usage_function=usage

# ============================================
# CHECKS
# ============================================
pass=0
warn=0
fail=0

check_result() {
    local status="$1"
    local message="$2"
    local fix_hint="${3:-}"

    case "$status" in
        PASS)
            echo -e "  ${GREEN}✓${NC} ${message}"
            pass=$((pass + 1))
            ;;
        WARN)
            echo -e "  ${YELLOW}⚠${NC} ${message}"
            warn=$((warn + 1))
            if [[ -n "$fix_hint" ]]; then
                echo -e "     ${CYAN}→${NC} ${fix_hint}"
            fi
            ;;
        FAIL)
            echo -e "  ${RED}✗${NC} ${message}"
            fail=$((fail + 1))
            if [[ -n "$fix_hint" ]]; then
                echo -e "     ${CYAN}→${NC} ${fix_hint}"
            fi
            ;;
    esac
}

do_fix() {
    if ! $FIX_MODE; then
        return 1
    fi
    local description="$1"
    shift
    log_info "Correction: ${description}..."
    "$@" && check_result PASS "${description} corrigé" || check_result WARN "Échec de correction: ${description}"
}

check_system() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ Système ═══${NC}"

    # RAM
    local total_mem
    total_mem=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ $total_mem -lt 4096 ]]; then
        check_result WARN "RAM: ${total_mem}MB (minimum 4096MB recommandé)" "Ajoutez de la RAM ou réduisez les limites mémoire des conteneurs"
    else
        check_result PASS "RAM: ${total_mem}MB"
    fi

    # Docker
    if docker info &>/dev/null; then
        check_result PASS "Docker actif"
    else
        check_result FAIL "Docker inactif" "Exécutez: systemctl start docker"
    fi

    # GPU
    if detect_nvidia_gpu &>/dev/null; then
        local gpu_info
        gpu_info=$(detect_nvidia_gpu)
        if detect_nvidia_runtime; then
            check_result PASS "GPU NVIDIA: ${gpu_info}"
        else
            check_result WARN "GPU NVIDIA détecté mais runtime Docker non configuré" "Exécutez: sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"
        fi
    fi

    # UFW
    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            check_result PASS "UFW actif"
        else
            check_result WARN "UFW inactif" "Activez avec: ufw enable"
        fi
    fi
}

check_network() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ Réseau ═══${NC}"

    if docker network inspect "$NETWORK_NAME" &>/dev/null; then
        check_result PASS "Réseau '${NETWORK_NAME}' présent"
    else
        check_result FAIL "Réseau '${NETWORK_NAME}' absent" "Créez-le: docker network create ${NETWORK_NAME}"
    fi
}

check_containers() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ Conteneurs ═══${NC}"

    local services=("traefik" "code-server" "ollama" "open-webui")

    for service in "${services[@]}"; do
        if docker_service_running "$service"; then
            local image
            image=$(get_container_image "$service")
            local uptime
            uptime=$(get_container_uptime "$service" | head -1)
            check_result PASS "${service} (${image}) — Démarré le ${uptime}"

            # Vérifier la version de l'image
            if [[ "$service" == "traefik" ]]; then
                local version
                version=$(docker exec traefik traefik version 2>/dev/null || echo "inconnue")
                check_result PASS "  Version Traefik: ${version}"
            fi
        elif docker_service_exists "$service"; then
            check_result FAIL "${service} existe mais n'est pas en cours d'exécution" "Redémarrez: docker restart ${service}"
        else
            check_result WARN "${service} n'est pas installé"
        fi
    done
}

check_healthchecks() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ Healthchecks ═══${NC}"

    local services=("traefik" "code-server" "ollama" "open-webui")

    for service in "${services[@]}"; do
        if docker_service_running "$service"; then
            local health
            health=$(docker inspect "$service" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
            case "$health" in
                healthy) check_result PASS "${service}: healthcheck OK" ;;
                unhealthy) check_result FAIL "${service}: healthcheck UNHEALTHY" "Consultez les logs: docker logs ${service}" ;;
                starting) check_result WARN "${service}: healthcheck en cours" ;;
                none) check_result WARN "${service}: pas de healthcheck configuré" ;;
            esac
        fi
    done
}

check_traefik() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ Traefik ═══${NC}"

    if ! docker_service_running "traefik"; then
        check_result WARN "Traefik non actif — vérification ignorée"
        return
    fi

    # Dashboard auth configuré ?
    if [[ -f "$TRAEFIK_DIR/config/.htpasswd" ]]; then
        check_result PASS "Dashboard: authentification configurée"
    else
        check_result WARN "Dashboard: pas d'authentification" "Exécutez: sudo ./update-ai-suite.sh"
    fi

    # Middlewares
    if [[ -f "$TRAEFIK_DIR/config/middlewares.yml" ]]; then
        check_result PASS "Middlewares: configurés"
    else
        check_result WARN "Middlewares: non configurés" "Exécutez: sudo ./update-ai-suite.sh"
    fi

    # Certificats SSL
    local cert_count
    cert_count=$(docker exec traefik traefik certificates list 2>/dev/null | grep -c "Domain" || echo "0")
    if [[ "$cert_count" -gt 0 ]]; then
        check_result PASS "Certificats SSL: ${cert_count}"
    else
        local logs
        logs=$(docker logs traefik 2>&1 | grep -i "acme\|certificate" | tail -3)
        if [[ -n "$logs" ]]; then
            check_result WARN "Certificats SSL en cours d'obtention"
            echo -e "     ${logs}"
        else
            check_result WARN "Aucun certificat SSL trouvé" "Vérifiez: docker logs traefik"
        fi
    fi
}

check_ollama() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ Ollama ═══${NC}"

    if ! docker_service_running "ollama"; then
        check_result WARN "Ollama non actif — vérification ignorée"
        return
    fi

    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        check_result PASS "API Ollama: répond"

        local model_count
        model_count=$(curl -s http://localhost:11434/api/tags | jq '.models | length' 2>/dev/null || echo "0")
        if [[ "$model_count" -gt 0 ]]; then
            check_result PASS "Modèles installés: ${model_count}"
            curl -s http://localhost:11434/api/tags | jq -r '.models[] | "     • \(.name) (\((.size / 1e9 | floor))GB)"' 2>/dev/null || true
        else
            check_result WARN "Aucun modèle installé" "Exécutez: sudo ./install-ollama-models.sh"
        fi
    else
        check_result FAIL "API Ollama: ne répond pas" "Vérifiez: docker logs ollama"
    fi
}

check_backups() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ Sauvegardes ═══${NC}"

    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_count
        backup_count=$(find "$BACKUP_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)
        if [[ "$backup_count" -gt 0 ]]; then
            check_result PASS "Sauvegardes: ${backup_count} fichier(s)"
            ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -3 | while read -r line; do
                echo -e "     ${line}"
            done
        else
            check_result WARN "Aucune sauvegarde trouvée" "Exécutez: sudo ./backup-ai-suite.sh backup"
        fi
    else
        check_result WARN "Dossier de sauvegarde inexistant" "Créez-le: mkdir -p ${BACKUP_DIR}"
    fi
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    parse_common_args "$@"
    local remaining="${_COMMON_REMAINING:-}"

    for arg in $remaining; do
        case "$arg" in
            --fix) FIX_MODE=true ;;
            -h|--help) usage; exit 0 ;;
            --version) echo "Coolify AI Suite v${AI_SUITE_VERSION}"; exit 0 ;;
            *) log_error "Argument inconnu: ${arg}"; usage; exit 1 ;;
        esac
    done

    require_root
    load_env

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Coolify AI Suite v${AI_SUITE_VERSION} — Diagnostic           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"

    if $FIX_MODE; then
        echo -e "${YELLOW}  Mode correction automatique activé${NC}"
    fi
    echo ""

    check_system
    check_network
    check_containers
    check_healthchecks
    check_traefik
    check_ollama
    check_backups

    # Résumé
    echo ""
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "  Résultat: ${GREEN}${pass} OK${NC} / ${YELLOW}${warn} avertissements${NC} / ${RED}${fail} erreurs${NC}"
    if [[ $fail -gt 0 ]]; then
        echo -e "  ${YELLOW}Utilisez --fix pour tenter une correction automatique${NC}"
    elif [[ $warn -gt 0 ]]; then
        echo -e "  ${YELLOW}Certains avertissements peuvent nécessiter votre attention${NC}"
    else
        echo -e "  ${GREEN}Tout est en ordre !${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
