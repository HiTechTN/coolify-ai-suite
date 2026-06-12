#!/bin/bash
# check-public-ip.sh - Vérifier et alerter en cas de changement d'IP publique
# Author: Mohamed Azmi KAANICHE
# Version: 3.0
#
# Usage: sudo ./check-public-ip.sh [options]
#
# Options:
#   -h, --help       Afficher cette aide
#   --fix            Mettre à jour la configuration locale
#   --cron           Mode silencieux pour cron (journalisation uniquement)
#   --ddns           Mettre à jour les enregistrements DNS (Cloudflare)
#   --setup-ddns     Assistant de configuration DDNS Cloudflare
#   --install-cron   Installer la tâche cron pour DDNS automatique
#   --no-color       Désactiver les couleurs
#   --log FILE       Fichier de log
#   --version        Afficher la version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

LOG_FILE="${LOG_FILE:-/var/log/ai-suite-ipcheck.log}"
STATE_FILE="${STATE_FILE:-/opt/ai-suite/.last-known-ip}"

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    check-public-ip.sh — Vérification IP publique + DDNS automatique

${BOLD}SYNOPSIS${NC}
    sudo ./check-public-ip.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Compare l'IP publique du serveur avec le DNS. Avec --ddns, met à jour
    automatiquement les enregistrements A via Cloudflare en cas de changement.

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --fix            Mettre à jour FIXED_IP dans .env + redémarrer Traefik
    --cron           Mode silencieux (journalisation seule, pas de sortie)
    --ddns           Mettre à jour les enregistrements DNS si IP changée
    --setup-ddns     Assistant interactif de configuration DDNS Cloudflare
    --install-cron   Installer la tâche cron (toutes les 5 minutes)
    --no-color       Désactiver les couleurs
    --log FILE       Fichier de log
    --version        Afficher la version

${BOLD}CONFIGURATION${NC}
    Variables dans .env :
      DOMAIN              Domaine à vérifier (ex: hitech.tn)
      FIXED_IP            IP fixe de référence (optionnelle)
      DNS_SERVERS         Serveurs DNS pour la résolution
      DDNS_ENABLED        Activer le DDNS automatique (true/false)
      DDNS_PROVIDER       Fournisseur DNS (cloudflare)
      CLOUDFLARE_API_TOKEN Token API Cloudflare
      CLOUDFLARE_ZONE_ID  Zone ID Cloudflare (optionnel, détection auto)

${BOLD}EXEMPLES${NC}
    sudo ./check-public-ip.sh
    sudo ./check-public-ip.sh --fix
    sudo ./check-public-ip.sh --ddns
    sudo ./check-public-ip.sh --cron
    sudo ./check-public-ip.sh --setup-ddns
    sudo ./check-public-ip.sh --install-cron
EOF
}

usage_function=usage

resolve_domain_ip() {
    local domain="$1"
    local ip=""

    if [[ -n "${DNS_SERVERS:-}" ]]; then
        for dns in $DNS_SERVERS; do
            ip=$(dig +short "@${dns}" "$domain" A 2>/dev/null | head -1)
            [[ -n "$ip" ]] && { echo "$ip"; return 0; }
        done
    fi

    ip=$(dig +short "$domain" A 2>/dev/null | head -1)
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }

    ip=$(host "$domain" 2>/dev/null | grep "has address" | awk '{print $NF}' | head -1)
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }

    echo ""
    return 1
}

# ============================================
# POINT D'ENTRÉE
# ============================================
main() {
    # Parse arguments (sans subshell pour que exit 0 fonctionne)
    local mode="normal"
    for arg in "$@"; do
        case "$arg" in
            -h|--help) usage; exit 0 ;;
            --version) echo "Coolify AI Suite v${AI_SUITE_VERSION}"; exit 0 ;;
            --fix) mode="fix" ;;
            --cron) mode="cron" ;;
            --ddns) mode="ddns" ;;
            --setup-ddns) mode="setup-ddns" ;;
            --install-cron) mode="install-cron" ;;
            --no-color) NO_COLOR=true ;;
            --log) ;;
            *) log_error "Argument inconnu: ${arg}"; usage; exit 1 ;;
        esac
    done

    local is_cron=false

    [[ "$mode" == "cron" ]] && is_cron=true

    if $is_cron; then
        exec >/dev/null 2>&1
    fi

    require_root
    load_env

    DOMAIN="${DOMAIN:-}"

    # Modes spéciaux (ne nécessitent pas de domaine)
    case "$mode" in
        setup-ddns)
            if [[ -z "$DOMAIN" ]]; then
                read -p "Domaine à configurer (ex: hitech.tn): " DOMAIN
            fi
            setup_cloudflare_ddns
            return $?
            ;;
        install-cron)
            install_ddns_cron
            return $?
            ;;
    esac

    if [[ -z "$DOMAIN" ]]; then
        if [[ "$mode" == "normal" ]]; then
            log_warning "DOMAIN non défini dans .env. Vérifications DNS ignorées."
        fi
    fi

    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  Vérification IP Publique               ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""

    local public_ip
    public_ip=$(get_public_ip)
    if [[ -z "$public_ip" ]]; then
        log_error "Impossible de détecter l'IP publique"
        exit 1
    fi
    log_success "IP publique détectée: ${BOLD}${public_ip}${NC}"

    local dns_ip=""
    if [[ -n "$DOMAIN" ]]; then
        dns_ip=$(resolve_domain_ip "$DOMAIN")
        if [[ -n "$dns_ip" ]]; then
            log_success "DNS ${DOMAIN} → ${BOLD}${dns_ip}${NC}"
        else
            log_warning "Impossible de résoudre ${DOMAIN}"
        fi
    fi

    if [[ -n "${FIXED_IP:-}" ]]; then
        echo ""
        echo -e "${BOLD}Comparaison avec l'IP fixe (${FIXED_IP}):${NC}"
        if [[ "$public_ip" == "$FIXED_IP" ]]; then
            log_success "L'IP publique correspond à l'IP fixe"
        else
            log_warning "IP publique (${public_ip}) ≠ IP fixe (${FIXED_IP})"
            log_warning "Mettez à jour FIXED_IP dans .env si le changement est permanent"
        fi
    fi

    if [[ -n "$dns_ip" ]]; then
        echo ""
        echo -e "${BOLD}Vérification DNS:${NC}"
        if [[ "$public_ip" == "$dns_ip" ]]; then
            log_success "IP publique cohérente avec le DNS"
        else
            log_warning "IP publique (${public_ip}) ≠ DNS (${dns_ip})"
            echo -e "  Action: A ${DOMAIN} → ${public_ip}"
            echo -e "          A *.${DOMAIN} → ${public_ip}"
        fi
    fi

    # Sauvegarder l'IP dans l'état
    local last_ip=""
    [[ -f "$STATE_FILE" ]] && last_ip=$(cat "$STATE_FILE")

    local ip_changed=false
    if [[ "$public_ip" != "$last_ip" ]]; then
        echo "$public_ip" > "$STATE_FILE"
        if [[ -n "$last_ip" ]]; then
            log_warning "IP changée: ${last_ip} → ${public_ip}"
            ip_changed=true
        else
            log_info "IP initiale enregistrée: ${public_ip}"
        fi
    fi

    # Mode --fix
    if [[ "$mode" == "fix" ]]; then
        echo ""
        echo -e "${YELLOW}Tentative de mise à jour de la configuration...${NC}"

        if [[ -f "$SCRIPT_DIR/.env" ]]; then
            sed -i "s/^FIXED_IP=.*/FIXED_IP=${public_ip}/" "$SCRIPT_DIR/.env" 2>/dev/null || true
            log_success ".env mis à jour avec FIXED_IP=${public_ip}"
        fi

        if docker_service_exists "traefik"; then
            log_info "Redémarrage de Traefik..."
            docker restart traefik 2>/dev/null && log_success "Traefik redémarré" || log_warning "Échec redémarrage Traefik"
        fi
    fi

    # Mode --ddns : mise à jour DNS automatique si IP changée ou différente du DNS
    if [[ "$mode" == "ddns" ]] || { [[ "$mode" == "cron" ]] && [[ "${DDNS_ENABLED:-false}" == "true" ]]; }; then
        if $ip_changed || { [[ -n "$dns_ip" ]] && [[ "$public_ip" != "$dns_ip" ]]; }; then
            if [[ -n "$DOMAIN" ]]; then
                log_info "Lancement de la mise à jour DDNS..."
                ddns_update "$DOMAIN" "$public_ip" || log_warning "DDNS : échec de la mise à jour"
            fi
        else
            log_info "DDNS : aucune mise à jour nécessaire"
        fi
    fi

    # Résumé
    echo ""
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    if [[ "$public_ip" == "${dns_ip:-}" || "$public_ip" == "${FIXED_IP:-}" ]]; then
        echo -e "${GREEN}✓ Aucune action requise${NC}"
    else
        echo -e "${YELLOW}⚠ Action recommandée (voir ci-dessus)${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
