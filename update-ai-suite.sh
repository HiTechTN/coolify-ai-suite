#!/bin/bash
# update-ai-suite.sh - Mise à jour de Coolify AI Suite
# Version: 1.0
#
# Usage: sudo ./update-ai-suite.sh [options]
#
# Options:
#   -h, --help       Afficher cette aide
#   --dry-run        Simuler sans modifier
#   --force          Forcer la mise à jour
#   --no-color       Désactiver les couleurs
#   --version        Afficher la version
#
# Ce script met à jour les scripts, la configuration et les services
# de la Coolify AI Suite depuis le dépôt Git.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

LOG_FILE="/var/log/ai-suite-update.log"

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    update-ai-suite.sh — Mise à jour de Coolify AI Suite

${BOLD}SYNOPSIS${NC}
    sudo ./update-ai-suite.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Met à jour les scripts, la configuration, et redémarre les services
    de la Coolify AI Suite depuis le dépôt Git.

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --dry-run        Simuler sans modifier
    --force          Forcer la mise à jour
    --no-color       Désactiver les couleurs
    --version        Afficher la version
EOF
}

usage_function=usage

# ============================================
# PARSE DES ARGUMENTS
# ============================================
parse_args() {
    parse_common_args "$@"
    local remaining="${_COMMON_REMAINING:-}"
    if [[ -n "$remaining" ]]; then
        log_error "Argument inconnu: ${remaining}"
        usage
        exit 1
    fi
}

# ============================================
# FONCTIONS DE MISE À JOUR
# ============================================
update_from_git() {
    log "Mise à jour depuis le dépôt Git..."

    if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
        log_warning "Ce n'est pas un dépôt Git. Impossible de mettre à jour automatiquement."
        log_warning "Téléchargez la dernière version depuis https://github.com/HiTechTN/coolify-ai-suite"
        return 1
    fi

    local current_branch
    current_branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

    log_info "Branche actuelle: ${current_branch}"

    # Sauvegarder la config locale
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        cp "$SCRIPT_DIR/.env" /tmp/ai-suite-env-backup
        log_info "Configuration .env sauvegardée dans /tmp/ai-suite-env-backup"
    fi

    run_cmd "Pull depuis Git" bash -c "cd '${SCRIPT_DIR}' && git pull origin '${current_branch}'"

    # Restaurer la config
    if [[ -f /tmp/ai-suite-env-backup ]]; then
        mv /tmp/ai-suite-env-backup "$SCRIPT_DIR/.env"
        chmod 600 "$SCRIPT_DIR/.env"
        log_success "Configuration .env restaurée"
    fi

    # Rendre les scripts exécutables
    run_cmd "Rendre les scripts exécutables" \
        bash -c "chmod +x '${SCRIPT_DIR}'/*.sh '${SCRIPT_DIR}/lib'/*.sh 2>/dev/null || true"

    log_success "Mise à jour Git terminée"
}

update_images() {
    log "Mise à jour des images Docker..."

    local services=("$AI_SUITE_DIR/traefik" "$AI_SUITE_DIR/code-server" "$AI_SUITE_DIR/ollama" "$AI_SUITE_DIR/open-webui" "$AI_SUITE_DIR/watchtower")

    for service_dir in "${services[@]}"; do
        if [[ -f "$service_dir/docker-compose.yml" ]]; then
            local name
            name=$(basename "$service_dir")
            log_info "Mise à jour de l'image pour ${name}..."
            run_cmd "Pull image ${name}" \
                bash -c "cd '${service_dir}' && docker compose pull 2>/dev/null || true"
            run_cmd "Redémarrage de ${name}" \
                bash -c "cd '${service_dir}' && docker compose up -d --remove-orphans 2>/dev/null || true"
        fi
    done

    log_success "Images Docker mises à jour"
}

update_config() {
    log "Mise à jour de la configuration..."

    # Re-générer les middlewares Traefik si le fichier n'existe pas
    if [[ ! -f "$TRAEFIK_DIR/config/middlewares.yml" && -d "$TRAEFIK_DIR" ]]; then
        log_info "Génération des middlewares Traefik manquants..."
        create_traefik_dashboard_middleware
    fi

    # Vérifier que Traefik tourne
    if docker_service_running "traefik"; then
        run_cmd "Rechargement de Traefik" docker exec traefik traefik reload 2>/dev/null || true
    fi

    log_success "Configuration mise à jour"
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    setup_trap
    parse_args "$@"
    require_root
    require_docker
    load_env

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Coolify AI Suite — Mise à jour        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    update_from_git
    update_images
    update_config

    echo ""
    echo -e "${GREEN}✓ Mise à jour terminée avec succès !${NC}"
    echo -e "  Version actuelle: ${BOLD}v${AI_SUITE_VERSION}${NC}"
    echo -e "  Exécutez ${BOLD}./check-ai-suite-status.sh${NC} pour vérifier l'état"
    echo ""
}

main "$@"
