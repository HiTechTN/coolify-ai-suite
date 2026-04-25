#!/bin/bash
# backup-ai-suite.sh - Sauvegarde et restauration Coolify AI Suite
# Author: Mohamed Azmi KAANICHE
# Version: 1.0

set -euo pipefail

# ============================================
# COULEURS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================
# CONFIGURATION
# ============================================
readonly BACKUP_DIR="${BACKUP_DIR:-/opt/backups/ai-suite}"
readonly AI_SUITE_DIR="/opt/ai-suite"
readonly RETENTION_DAYS="${RETENTION_DAYS:-7}"

# ============================================
# FONCTIONS
# ============================================
log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [COMMANDE]

Commandes:
  backup          Créer une sauvegarde complète
  restore FILE    Restaurer depuis une sauvegarde
  list           Lister les sauvegardes disponibles
  clean          Supprimer les anciennes sauvegardes
  status         Afficher le statut des volumes

Exemples:
  $0 backup                    # Sauvegarder maintenant
  $0 restore backup_20260425.tar.gz  # Restaurer
  $0 clean                      # Nettoyer les anciennes (>7 jours)
EOF
}

# ============================================
# SAUVEGARDE
# ============================================
do_backup() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="ai-suite_${timestamp}.tar.gz"
    
    log "Démarrage de la sauvegarde..."
    mkdir -p "$BACKUP_DIR"
    
    # Sauvegarder la configuration
    log "Sauvegarde de la configuration..."
    tar -czf "$BACKUP_DIR/$backup_file" \
        -C /opt ai-suite \
        --exclude='ai-suite/**/node_modules' \
        --exclude='ai-suite/**/*.pyc' \
        --exclude='ai-suite/code-server/config/__pycache__' \
        2>/dev/null || true
    
    # Sauvegarder les volumes Docker
    log "Sauvegarde des volumes Docker..."
    for volume in $(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '^(ai-suite_|ollama|open-webui)'); do
        local vol_backup="${volume}_${timestamp}.tar.gz"
        docker run --rm \
            -v "${volume}:/data" \
            -v "${BACKUP_DIR}:/backup" \
            alpine:latest \
            tar -czf "/backup/${vol_backup}" -C / data
        success "Volume $volume sauvegardé"
    done
    
    # Manifeste
    cat > "$BACKUP_DIR/manifest_${timestamp}.txt" << EOF
BACKUP_DATE=$timestamp
OLLAMA_PORT=${OLLAMA_PORT:-11434}
CODE_SERVER_PORT=${CODE_SERVER_PORT:-8443}
OPEN_WEBUI_PORT=${OPEN_WEBUI_PORT:-3000}
COOLIFY_PORT=${COOLIFY_PORT:-8000}
EOF
    
    success "Sauvegarde terminée: $BACKUP_DIR/$backup_file"
    echo ""
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -5
}

# ============================================
# RESTAURATION
# ============================================
do_restore() {
    local backup_file="$1"
    
    if [[ ! -f "$BACKUP_DIR/$backup_file" ]]; then
        error "Fichier de sauvegarde non trouvé: $backup_file"
        exit 1
    fi
    
    log "Restauration depuis: $backup_file"
    read -p "Cela écrasera les données actuelles. Continuer ? (o/N): " confirm
    [[ "$confirm" != "o" && "$confirm" != "O" ]] && exit 0
    
    # Arrêter les services
    log "Arrêt des services..."
    cd "$AI_SUITE_DIR" 2>/dev/null
    for dir in code-server ollama open-webui; do
        [[ -d "$AI_SUITE_DIR/$dir" ]] && docker compose -f "$AI_SUITE_DIR/$dir/docker-compose.yml" down 2>/dev/null || true
    done
    
    # Restaurer
    log "Extraction des fichiers..."
    tar -xzf "$BACKUP_DIR/$backup_file" -C /
    
    success "Restauration terminée"
}

# ============================================
# LISTE DES SAUVEGARDES
# ============================================
do_list() {
    log "Sauvegardes disponibles dans $BACKUP_DIR:"
    echo ""
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print "  " $9, "(" $5 ")"}' || echo "  Aucune sauvegarde"
}

# ============================================
# NETTOYAGE
# ============================================
do_clean() {
    log "Suppression des sauvegardes de plus de $RETENTION_DAYS jours..."
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime "+$RETENTION_DAYS" -delete
    success "Nettoyage terminé"
}

# ============================================
# STATUT
# ============================================
do_status() {
    log "Statut des volumes Docker:"
    docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '^(ai-suite_|ollama|open-webui)' | while read vol; do
        local size
        size=$(docker volume inspect "$vol" --format '{{.Size}}' 2>/dev/null || echo "unknown")
        echo "  • $vol: $size"
    done
}

# ============================================
# POINT D'ENTRÉE
# ============================================
case "${1:-}" in
    backup)  do_backup ;;
    restore) [[ -z "$2" ]] && { error "Spécifiez le fichier: $0 restore FILE"; exit 1; }; do_restore "$2" ;;
    list)    do_list ;;
    clean)   do_clean ;;
    status)  do_status ;;
    *)       usage ;;
esac