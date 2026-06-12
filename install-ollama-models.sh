#!/bin/bash
# install-ollama-models.sh - Installer les modèles AI pour Ollama
# Version: 2.0
#
# Usage: sudo ./install-ollama-models.sh [options] [modèles...]
#
# Options:
#   -h, --help       Afficher cette aide
#   --dry-run        Simuler sans télécharger
#   --list           Lister les modèles disponibles
#   --no-color       Désactiver les couleurs
#   --version        Afficher la version
#
# Exemples:
#   sudo ./install-ollama-models.sh
#   sudo ./install-ollama-models.sh --model qwen2.5-coder:7b
#   sudo ./install-ollama-models.sh llama3.2:3b deepseek-coder-v2
#   sudo ./install-ollama-models.sh --list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

LOG_FILE="/var/log/ai-suite-ollama-models.log"

# Modèles recommandés par catégorie
CATEGORIES=(
    "Code:qwen2.5-coder:3b,qwen2.5-coder:7b,qwen2.5-coder:14b,deepseek-coder-v2:16b-lite-instruct-q2_K"
    "Général:llama3.2:3b,llama3.2:1b,phi3:3.8b,phi3:14b,mistral:7b"
    "Spécialisé:mixtral:8x7b,gemma2:9b,llama3.1:8b"
)

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    install-ollama-models.sh — Installer des modèles Ollama

${BOLD}SYNOPSIS${NC}
    sudo ./install-ollama-models.sh [OPTIONS] [MODÈLES...]

${BOLD}DESCRIPTION${NC}
    Télécharge et installe des modèles de langage pour Ollama.
    Sans argument, un menu interactif vous guide dans le choix.

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --dry-run        Simuler sans télécharger
    --list           Lister les modèles disponibles par catégorie
    --no-color       Désactiver les couleurs
    --version        Afficher la version

${BOLD}EXEMPLES${NC}
    sudo ./install-ollama-models.sh
    sudo ./install-ollama-models.sh qwen2.5-coder:7b
    sudo ./install-ollama-models.sh llama3.2:3b mistral:7b
    sudo ./install-ollama-models.sh --list
EOF
}

usage_function=usage

# ============================================
# PARSE DES ARGUMENTS
# ============================================
parse_args() {
    local models=()
    local show_list=false

    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=true ;;
            --no-color) NO_COLOR=true ;;
            --list) show_list=true ;;
            --model) ;;
            *)
                if [[ ! "$arg" =~ ^-- ]]; then
                    models+=("$arg")
                fi
                ;;
        esac
    done

    echo "$show_list"
    if [[ ${#models[@]} -gt 0 ]]; then
        local IFS='|'
        echo "${models[*]}"
    fi
}

wait_for_ollama() {
    log_info "Attente d'Ollama..."
    local max_attempts=30
    local attempt=0

    until curl -s http://localhost:11434/api/tags >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            log_error "Ollama n'a pas démarré après ${max_attempts} tentatives"
            log_error "Vérifiez: sudo docker logs ollama"
            exit 1
        fi
        echo -n "."
        sleep 5
    done
    echo ""
    log_success "Ollama est prêt !"
}

install_models() {
    local models=("$@")

    if [[ ${#models[@]} -eq 0 ]]; then
        log_error "Aucun modèle spécifié"
        return 1
    fi

    echo ""
    log_info "Modèles à installer :"
    for model in "${models[@]}"; do
        echo -e "  ${CYAN}•${NC} ${BOLD}$model${NC}"
    done
    echo ""

    if ! $DRY_RUN; then
        read -p "Continuer ? (O/n): " confirm
        [[ "$confirm" == "n" || "$confirm" == "N" ]] && { log_info "Annulé"; return; }
    fi

    for model in "${models[@]}"; do
        echo ""
        log_info "Téléchargement de ${model}..."
        if $DRY_RUN; then
            log_warning "[DRY-RUN] ollama pull ${model}"
        else
            if ollama pull "$model"; then
                log_success "${model} installé"
            else
                log_warning "Échec du téléchargement de ${model}"
            fi
        fi
    done
}

show_interactive_menu() {
    local selected=()

    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Installation de modèles Ollama     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    for category_entry in "${CATEGORIES[@]}"; do
        local cat_name="${category_entry%%:*}"
        local cat_models="${category_entry#*:}"
        local IFS=','

        echo -e "${CYAN}━━━ ${cat_name} ━━━${NC}"

        local idx=0
        for model in $cat_models; do
            idx=$((idx + 1))
            echo -e "  [${idx}] ${model}"
        done
        echo ""
    done

    echo -e "${YELLOW}Entrez les numéros séparés par des espaces,${NC}"
    echo -e "${YELLOW}ou 'all' pour tout installer, ou 'q' pour quitter.${NC}"
    echo -ne "${BOLD}Votre choix : ${NC}"
    read -r choices

    case "$choices" in
        q|Q) exit 0 ;;
        all|a|A)
            for category_entry in "${CATEGORIES[@]}"; do
                local cat_models="${category_entry#*:}"
                local IFS=','
                for model in $cat_models; do
                    selected+=("$model")
                done
            done
            ;;
        *)
            local global_idx=0
            for category_entry in "${CATEGORIES[@]}"; do
                local cat_models="${category_entry#*:}"
                local IFS=','
                for model in $cat_models; do
                    global_idx=$((global_idx + 1))
                    for choice in $choices; do
                        if [[ "$choice" == "$global_idx" ]]; then
                            selected+=("$model")
                        fi
                    done
                done
            done
            ;;
    esac

    if [[ ${#selected[@]} -eq 0 ]]; then
        log_warning "Aucun modèle sélectionné"
        exit 0
    fi

    install_models "${selected[@]}"
}

show_list() {
    echo ""
    echo -e "${CYAN}Modèles disponibles par catégorie :${NC}"
    echo ""

    for category_entry in "${CATEGORIES[@]}"; do
        local cat_name="${category_entry%%:*}"
        local cat_models="${category_entry#*:}"
        echo -e "${BOLD}${cat_name}:${NC}"
        local IFS=','
        for model in $cat_models; do
            echo -e "  • ${model}"
        done
        echo ""
    done
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    # Handle help/version before parse_args (évite subshell exit bug)
    for arg in "$@"; do
        case "$arg" in -h|--help) usage; exit 0 ;; --version) echo "Coolify AI Suite v${AI_SUITE_VERSION}"; exit 0 ;; esac
    done

    local args
    args=$(parse_args "$@")

    local show_list="${args%%$'\n'*}"
    local models_line="${args#*$'\n'}"

    if [[ "$show_list" == "true" ]]; then
        show_list
        exit 0
    fi

    require_root
    wait_for_ollama

    local models=()
    if [[ -n "$models_line" ]]; then
        local IFS='|'
        for m in $models_line; do
            models+=("$m")
        done
    fi

    if [[ ${#models[@]} -gt 0 ]]; then
        install_models "${models[@]}"
    else
        show_interactive_menu
    fi

    # Résumé
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Modèles disponibles :${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    curl -s http://localhost:11434/api/tags | jq -r '.models[] | "  • " + .name + " (" + (.size / 1e9 | floor | tostring) + "GB)"' 2>/dev/null || echo "  (aucun modèle)"
    echo ""
}

main "$@"
