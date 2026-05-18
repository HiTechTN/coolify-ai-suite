#!/bin/bash
# check-public-ip.sh - Vérifier et alerter en cas de changement d'IP publique
# Author: Mohamed Azmi KAANICHE
# Version: 1.0
#
# Usage: sudo ./check-public-ip.sh
#   ou : sudo ./check-public-ip.sh --fix    (tente de mettre à jour la configuration)
#   ou : sudo ./check-public-ip.sh --cron   (mode silencieux pour cron)
#
# Ce script compare l'IP publique du serveur avec l'enregistrement DNS
# du domaine configuré. Utile si le domaine pointe vers une IP fixe
# mais que le serveur peut changer d'IP.

set -euo pipefail

# ============================================
# COULEURS
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================
# CONFIGURATION
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/ai-suite-ipcheck.log}"
STATE_FILE="${STATE_FILE:-/opt/ai-suite/.last-known-ip}"

# Charger .env si présent
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

DOMAIN="${DOMAIN:-}"
DNS_SERVERS="${DNS_SERVERS:-dns1.tunet.tn dns2.tunet.tn}"
FIXED_IP="${FIXED_IP:-196.203.63.49}"

# ============================================
# FONCTIONS
# ============================================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [[ "${2:-}" != "quiet" ]]; then
        echo -e "${CYAN}$1${NC}"
    fi
}

success() {
    echo -e "${GREEN}✓${NC} $1"
    log "[OK] $1" quiet
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "[WARN] $1" quiet
}

error() {
    echo -e "${RED}✗${NC} $1"
    log "[ERROR] $1" quiet
}

get_public_ip() {
    curl -s --max-time 10 https://api.ipify.org 2>/dev/null ||
    curl -s --max-time 10 https://ifconfig.me 2>/dev/null ||
    curl -s --max-time 10 https://icanhazip.com 2>/dev/null ||
    echo ""
}

resolve_domain_ip() {
    local domain="$1"
    local ip=""

    for dns in $DNS_SERVERS; do
        ip=$(dig +short "@${dns}" "$domain" A 2>/dev/null | head -1)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done

    # Fallback: résolution système
    ip=$(dig +short "$domain" A 2>/dev/null | head -1)
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi

    ip=$(host "$domain" 2>/dev/null | grep "has address" | awk '{print $NF}' | head -1)
    if [[ -n "$ip" ]]; then
        echo "$ip"
        return 0
    fi

    echo ""
    return 1
}

check_dependencies() {
    local missing=()
    for cmd in curl dig host; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Dépendances manquantes: ${missing[*]}"
        error "Installez: apt-get install -y dnsutils curl"
        exit 1
    fi
}

# ============================================
# VÉRIFICATION PRINCIPALE
# ============================================
main() {
    local mode="${1:-normal}"
    local is_cron=false

    [[ "$mode" == "--cron" ]] && is_cron=true

    # En mode cron, pas de sortie couleur
    if $is_cron; then
        exec >/dev/null 2>&1
    fi

    check_dependencies

    echo ""
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  Vérification IP Publique              ${NC}"
    echo -e "${BOLD}${CYAN}════════════════════════════════════════${NC}"
    echo ""

    # 1. IP publique actuelle du serveur
    local public_ip
    public_ip=$(get_public_ip)
    if [[ -z "$public_ip" ]]; then
        error "Impossible de détecter l'IP publique"
        exit 1
    fi
    success "IP publique detectée: ${BOLD}${public_ip}${NC}"

    # 2. Résolution DNS du domaine
    local dns_ip=""
    if [[ -n "$DOMAIN" ]]; then
        dns_ip=$(resolve_domain_ip "$DOMAIN")
        if [[ -n "$dns_ip" ]]; then
            success "DNS ${DOMAIN} → ${BOLD}${dns_ip}${NC}"
        else
            warn "Impossible de résoudre ${DOMAIN}"
        fi
    fi

    # 3. Comparer avec l'IP fixe de référence
    if [[ -n "$FIXED_IP" ]]; then
        echo ""
        echo -e "${BOLD}Comparaison avec l'IP fixe (${FIXED_IP}):${NC}"
        if [[ "$public_ip" == "$FIXED_IP" ]]; then
            success "L'IP publique correspond à l'IP fixe ${FIXED_IP}"
        else
            warn "L'IP publique (${public_ip}) diffère de l'IP fixe (${FIXED_IP})"
            warn "Vérifiez la configuration réseau ou le NAT"
        fi
    fi

    # 4. Comparer IP publique avec DNS
    if [[ -n "$dns_ip" ]]; then
        echo ""
        echo -e "${BOLD}Vérification de cohérence DNS:${NC}"
        if [[ "$public_ip" == "$dns_ip" ]]; then
            success "L'IP publique correspond à l'enregistrement DNS ✓"
        else
            warn "L'IP publique (${public_ip}) ≠ DNS (${dns_ip})"
            warn "Mettez à jour l'enregistrement A de ${DOMAIN} vers ${public_ip}"
            echo ""
            echo -e "  ${YELLOW}Action requise chez votre registrar :${NC}"
            echo -e "  A ${DOMAIN} → ${public_ip}"
            echo -e "  A *.${DOMAIN} → ${public_ip}"
        fi
    fi

    # 5. Sauvegarder l'IP dans l'état
    local last_ip=""
    [[ -f "$STATE_FILE" ]] && last_ip=$(cat "$STATE_FILE")

    if [[ "$public_ip" != "$last_ip" ]]; then
        echo "$public_ip" > "$STATE_FILE"
        if [[ -n "$last_ip" ]]; then
            log "IP changée: ${last_ip} → ${public_ip}" quiet
            warn "IP changée depuis la dernière vérification: ${last_ip} → ${public_ip}"
        else
            log "IP initiale enregistrée: ${public_ip}" quiet
        fi
    fi

    # 6. Mode --fix: tenter de mettre à jour la config locale
    if [[ "$mode" == "--fix" && -n "$dns_ip" && "$public_ip" != "$dns_ip" ]]; then
        echo ""
        echo -e "${YELLOW}Tentative de mise à jour de la configuration...${NC}"

        # Mettre à jour le .env du projet
        if [[ -f "$SCRIPT_DIR/.env" ]]; then
            sed -i "s/^FIXED_IP=.*/FIXED_IP=${public_ip}/" "$SCRIPT_DIR/.env" 2>/dev/null || true
            success ".env mis à jour avec FIXED_IP=${public_ip}"
        fi

        # Redémarrer Traefik pour forcer le rechargement SSL
        if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
            echo -e "  Redémarrage de Traefik..."
            docker restart traefik 2>/dev/null && success "Traefik redémarré" || warn "Impossible de redémarrer Traefik"
        fi

        warn "DNS non modifié automatiquement (serveurs: ${DNS_SERVERS})"
        warn "Mettez à jour manuellement l'enregistrement A chez votre registrar"
    fi

    # 7. Résumé
    echo ""
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    if [[ "$public_ip" == "${dns_ip:-}" || "$public_ip" == "$FIXED_IP" ]]; then
        echo -e "${GREEN}✓ Aucune action requise${NC}"
    else
        echo -e "${YELLOW}⚠ Action recommandée (voir ci-dessus)${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
