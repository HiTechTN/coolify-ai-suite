#!/bin/bash
# backup-ai-suite.sh - Sauvegarde et restauration complète Coolify AI Suite
# Author: Mohamed Azmi KAANICHE
# Version: 2.0
#
# Usage: sudo ./backup-ai-suite.sh [options] <commande>
#
# Commandes:
#   backup          Créer une sauvegarde complète
#   restore FILE    Restaurer depuis une sauvegarde
#   list            Lister les sauvegardes disponibles
#   clean           Supprimer les anciennes sauvegardes
#   status          Afficher le statut des volumes
#
# Options:
#   -h, --help       Afficher cette aide
#   --dry-run        Simuler sans sauvegarder
#   --no-color       Désactiver les couleurs
#   --log FILE       Fichier de log
#   --version        Afficher la version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

LOG_FILE="/var/log/ai-suite-backup.log"

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    backup-ai-suite.sh — Sauvegarde et restauration complète

${BOLD}SYNOPSIS${NC}
    sudo ./backup-ai-suite.sh [OPTIONS] <COMMANDE>

${BOLD}COMMANDES${NC}
    backup          Créer une sauvegarde complète
    restore FILE    Restaurer depuis une sauvegarde
    list            Lister les sauvegardes disponibles
    clean           Supprimer les sauvegardes de plus de RETENTION_DAYS jours
    status          Afficher le statut des volumes

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --dry-run        Simuler sans sauvegarder
    --no-color       Désactiver les couleurs
    --log FILE       Fichier de log
    --version        Afficher la version

${BOLD}EXEMPLES${NC}
    sudo ./backup-ai-suite.sh backup
    sudo ./backup-ai-suite.sh restore ai-suite_20260425.tar.gz
    sudo ./backup-ai-suite.sh list
    sudo ./backup-ai-suite.sh clean
EOF
}

usage_function=usage

# ============================================
# PARSE DES ARGUMENTS
# ============================================
parse_args() {
    local args=("$@")
    local command=""
    local rest=()

    for arg in "${args[@]}"; do
        case "$arg" in
            -h|--help) usage; exit 0 ;;
            --version) echo "Coolify AI Suite v${AI_SUITE_VERSION}"; exit 0 ;;
            backup|restore|list|clean|status) command="$arg" ;;
            --dry-run) DRY_RUN=true ;;
            --no-color) NO_COLOR=true ;;
            --log) ;;
            *)
                if [[ -z "$command" ]]; then
                    log_error "Commande inconnue: ${arg}"
                    usage
                    exit 1
                fi
                rest+=("$arg")
                ;;
        esac
    done

    echo "$command"
    if [[ ${#rest[@]} -gt 0 ]]; then
        echo "${rest[@]}"
    fi
}

# ============================================
# SAUVEGARDE COMPLÈTE
# ============================================
do_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="ai-suite_${timestamp}.tar.gz"
    local manifest_file="manifest_${timestamp}.txt"

    log "Démarrage de la sauvegarde complète..."
    mkdir -p "$BACKUP_DIR"

    # 1. Configuration AI Suite
    log "Sauvegarde de la configuration AI Suite..."
    run_cmd "Compression de ${AI_SUITE_DIR}" \
        tar -czf "${BACKUP_DIR}/${backup_file}" \
            -C / \
            opt/ai-suite \
            --exclude='opt/ai-suite/**/node_modules' \
            --exclude='opt/ai-suite/**/*.pyc' \
            --exclude='opt/ai-suite/code-server/config/__pycache__' \
            2>/dev/null || true

    # 2. Volumes Docker
    log "Sauvegarde des volumes Docker..."
    local volume_list
    volume_list=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '^(ai-suite_|ollama|open-webui|coolify)' || true)
    if [[ -n "$volume_list" ]]; then
        for volume in $volume_list; do
            local vol_backup="${volume}_${timestamp}.tar.gz"
            run_cmd "Sauvegarde du volume ${volume}" \
                docker run --rm \
                    -v "${volume}:/data" \
                    -v "${BACKUP_DIR}:/backup" \
                    alpine:latest \
                    tar -czf "/backup/${vol_backup}" -C / data
        done
    fi

    # 3. Certificats SSL Traefik
    if [[ -f "$TRAEFIK_DIR/acme/acme.json" ]]; then
        log "Sauvegarde des certificats SSL..."
        run_cmd "Copie de acme.json" \
            cp "$TRAEFIK_DIR/acme/acme.json" "${BACKUP_DIR}/acme_${timestamp}.json"
    fi

    # 4. Crontabs
    log "Sauvegarde des crontabs..."
    crontab -l 2>/dev/null > "${BACKUP_DIR}/crontab_${timestamp}.txt" || true

    # 5. Fichier .env
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        run_cmd "Copie de .env" \
            cp "$SCRIPT_DIR/.env" "${BACKUP_DIR}/env_${timestamp}.txt"
    fi

    # 6. Liste des modèles Ollama
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        curl -s http://localhost:11434/api/tags | jq -r '.models[] | "\(.name) \(.size)"' \
            > "${BACKUP_DIR}/ollama_models_${timestamp}.txt" 2>/dev/null || true
        log_success "Liste des modèles Ollama sauvegardée"
    fi

    # 7. Manifeste
    cat > "${BACKUP_DIR}/${manifest_file}" << MANIFEST_EOF
BACKUP_DATE=${timestamp}
AI_SUITE_VERSION=${AI_SUITE_VERSION}
DOMAIN=${DOMAIN:-}
OLLAMA_PORT=${OLLAMA_PORT}
CODE_SERVER_PORT=${CODE_SERVER_PORT}
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT}
COOLIFY_PORT=${COOLIFY_PORT}
TRAEFIK_ENABLED=$(docker_service_exists "traefik" && echo "true" || echo "false")
MANIFEST_EOF

    log_success "Sauvegarde terminée: ${BACKUP_DIR}/${backup_file}"
    echo ""
    ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | tail -5 || echo "  (aucun fichier)"
}

# ============================================
# RESTAURATION
# ============================================
do_restore() {
    local backup_file="$1"

    if [[ ! -f "$BACKUP_DIR/$backup_file" ]]; then
        # Essayer sans le chemin
        backup_file="${BACKUP_DIR}/${backup_file}"
        if [[ ! -f "$backup_file" ]]; then
            log_error "Fichier de sauvegarde non trouvé: ${1}"
            do_list
            exit 1
        fi
    fi

    log "Restauration depuis: ${backup_file}"
    echo -e "${YELLOW}⚠ Cela écrasera les données actuelles.${NC}"
    read -p "Continuer ? (o/N): " confirm
    [[ "$confirm" != "o" && "$confirm" != "O" ]] && { log_info "Restauration annulée"; exit 0; }

    # Arrêter les services
    log "Arrêt des services..."
    for dir in code-server ollama open-webui; do
        if [[ -d "$AI_SUITE_DIR/$dir" ]]; then
            docker compose -f "$AI_SUITE_DIR/$dir/docker-compose.yml" down 2>/dev/null || true
        fi
    done
    docker compose -f "$TRAEFIK_DIR/docker-compose.yml" down 2>/dev/null || true

    # Restaurer les fichiers
    log "Extraction des fichiers..."
    tar -xzf "$backup_file" -C /

    # Restaurer les volumes
    local timestamp
    timestamp=$(basename "$backup_file" | sed 's/ai-suite_//;s/\.tar\.gz//')
    for vol_backup in "${BACKUP_DIR}"/*_"${timestamp}".tar.gz; do
        [[ ! -f "$vol_backup" ]] && continue
        local vol_name
        vol_name=$(basename "$vol_backup" | sed "s/_${timestamp}\\.tar\\.gz//")
        log "Restauration du volume ${vol_name}..."
        docker volume create "${vol_name}" 2>/dev/null || true
        docker run --rm \
            -v "${vol_name}:/data" \
            -v "${BACKUP_DIR}:/backup" \
            alpine:latest \
            tar -xzf "/backup/$(basename "$vol_backup")" -C / data
    done

    # Restaurer les certificats SSL
    local acme_backup="${BACKUP_DIR}/acme_${timestamp}.json"
    if [[ -f "$acme_backup" ]]; then
        mkdir -p "$TRAEFIK_DIR/acme"
        cp "$acme_backup" "$TRAEFIK_DIR/acme/acme.json"
        chmod 600 "$TRAEFIK_DIR/acme/acme.json"
        log_success "Certificats SSL restaurés"
    fi

    # Redémarrer les services
    log "Redémarrage des services..."
    for dir in "$TRAEFIK_DIR" "$AI_SUITE_DIR"/code-server "$AI_SUITE_DIR"/ollama "$AI_SUITE_DIR"/open-webui; do
        if [[ -f "$dir/docker-compose.yml" ]]; then
            docker compose -f "$dir/docker-compose.yml" up -d 2>/dev/null || true
        fi
    done

    log_success "Restauration terminée"
}

# ============================================
# LISTE
# ============================================
do_list() {
    log "Sauvegardes disponibles dans ${BACKUP_DIR}:"
    echo ""
    if ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null; then
        echo ""
        log_info "Pour restaurer: sudo ./backup-ai-suite.sh restore <fichier>"
    else
        echo "  Aucune sauvegarde trouvée"
    fi
}

# ============================================
# NETTOYAGE
# ============================================
do_clean() {
    log "Suppression des sauvegardes de plus de ${RETENTION_DAYS} jours..."
    local count
    count=$(find "$BACKUP_DIR" -name "*.tar.gz" -mtime "+${RETENTION_DAYS}" 2>/dev/null | wc -l)
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null
    find "$BACKUP_DIR" -name "manifest_*.txt" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null
    find "$BACKUP_DIR" -name "acme_*.json" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null
    log_success "${count} sauvegarde(s) supprimée(s)"
}

# ============================================
# STATUT
# ============================================
do_status() {
    log "Statut des volumes Docker:"
    echo ""
    docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '^(ai-suite_|ollama|open-webui|coolify)' | \
        while read -r vol; do
            echo "  • $vol"
        done
    echo ""
    log_info "Taille du dossier de sauvegarde:"
    du -sh "$BACKUP_DIR" 2>/dev/null || echo "  (dossier inexistant)"
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    local args
    args=$(parse_args "$@")

    require_root

    local command="${args%% *}"
    local rest="${args#* }"

    case "$command" in
        backup)  do_backup ;;
        restore)
            local file="${rest#* }"
            if [[ -z "$file" ]]; then
                log_error "Spécifiez le fichier: $0 restore FILE"
                usage
                exit 1
            fi
            do_restore "$file"
            ;;
        list)    do_list ;;
        clean)   do_clean ;;
        status)  do_status ;;
        *)       usage ;;
    esac
}

main "$@"
