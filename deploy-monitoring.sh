#!/bin/bash
# deploy-monitoring.sh - Déployer la stack de monitoring optionnelle
# Version: 1.0
#
# Usage: sudo ./deploy-monitoring.sh [options]
#
# Options:
#   -h, --help       Afficher cette aide
#   --dry-run        Simuler sans déployer
#   --no-color       Désactiver les couleurs
#   --with-grafana   Déployer aussi Grafana + Prometheus (stack complète)
#   --remove         Supprimer la stack monitoring
#   --version        Afficher la version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config.sh"

LOG_FILE="/var/log/ai-suite-monitoring.log"

# ============================================
# USAGE
# ============================================
usage() {
    cat << EOF
${BOLD}NAME${NC}
    deploy-monitoring.sh — Stack de monitoring optionnelle

${BOLD}SYNOPSIS${NC}
    sudo ./deploy-monitoring.sh [OPTIONS]

${BOLD}DESCRIPTION${NC}
    Déploie cAdvisor pour la surveillance des conteneurs Docker.
    Avec --with-grafana, déploie aussi Prometheus + Grafana.

${BOLD}OPTIONS${NC}
    -h, --help       Afficher cette aide
    --dry-run        Simuler sans déployer
    --no-color       Désactiver les couleurs
    --with-grafana   Déployer Grafana + Prometheus (stack complète)
    --remove         Supprimer la stack monitoring
    --version        Afficher la version
EOF
}

usage_function=usage

# ============================================
# PARSE DES ARGUMENTS
# ============================================
WITH_GRAFANA=false
REMOVE=false

parse_args() {
    local remaining
    remaining=$(parse_common_args "$@")

    for arg in $remaining; do
        case "$arg" in
            --with-grafana) WITH_GRAFANA=true ;;
            --remove) REMOVE=true ;;
            -h|--help) usage; exit 0 ;;
            --version) echo "Coolify AI Suite v${AI_SUITE_VERSION}"; exit 0 ;;
            *) log_error "Argument inconnu: ${arg}"; usage; exit 1 ;;
        esac
    done
}

# ============================================
# DÉPLOIEMENT
# ============================================
deploy_cadvisor() {
    log "Déploiement de cAdvisor..."

    mkdir -p "${AI_SUITE_DIR}/monitoring"

    cat > "${AI_SUITE_DIR}/monitoring/docker-compose.yml" << CADVISOR_EOF
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.cadvisor.rule=Host(\`monitor.${TLD}\`)"
      - "traefik.http.routers.cadvisor.tls=true"
      - "traefik.http.routers.cadvisor.middlewares=dashboard-auth"
      - "traefik.http.services.cadvisor.loadbalancer.server.port=8080"

networks:
  ${NETWORK_NAME}:
    external: true
CADVISOR_EOF

    run_cmd "Démarrage de cAdvisor" \
        bash -c "cd '${AI_SUITE_DIR}/monitoring' && docker compose up -d"
}

deploy_grafana_stack() {
    log "Déploiement de Prometheus + Grafana..."

    mkdir -p "${AI_SUITE_DIR}/monitoring"

    # Prometheus config
    mkdir -p "${AI_SUITE_DIR}/monitoring/prometheus"
    cat > "${AI_SUITE_DIR}/monitoring/prometheus/prometheus.yml" << PROM_EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
PROM_EOF

    # Docker Compose complet
    cat > "${AI_SUITE_DIR}/monitoring/docker-compose.yml" << GRAFANA_EOF
services:
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.cadvisor.rule=Host(\`monitor.${TLD}\`)"
      - "traefik.http.routers.cadvisor.tls=true"
      - "traefik.http.routers.cadvisor.middlewares=dashboard-auth"
      - "traefik.http.services.cadvisor.loadbalancer.server.port=8080"

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
    labels:
      - "traefik.enable=false"

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus-data:/prometheus
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(\`prom.${TLD}\`)"
      - "traefik.http.routers.prometheus.tls=true"
      - "traefik.http.routers.prometheus.middlewares=dashboard-auth"
      - "traefik.http.services.prometheus.loadbalancer.server.port=9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD:-admin}
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - grafana-data:/var/lib/grafana
    networks:
      - ${NETWORK_NAME}
    restart: unless-stopped
    depends_on:
      - prometheus
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(\`grafana.${TLD}\`)"
      - "traefik.http.routers.grafana.tls=true"
      - "traefik.http.routers.grafana.middlewares=dashboard-auth"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"

networks:
  ${NETWORK_NAME}:
    external: true

volumes:
  prometheus-data:
  grafana-data:
GRAFANA_EOF

    run_cmd "Démarrage de la stack monitoring complète" \
        bash -c "cd '${AI_SUITE_DIR}/monitoring' && docker compose up -d"
}

remove_monitoring() {
    log "Suppression de la stack monitoring..."

    if [[ -f "${AI_SUITE_DIR}/monitoring/docker-compose.yml" ]]; then
        run_cmd "Arrêt et suppression des conteneurs" \
            bash -c "cd '${AI_SUITE_DIR}/monitoring' && docker compose down -v 2>/dev/null || true"
    fi

    if $DRY_RUN; then
        log_warning "[DRY-RUN] Suppression du dossier ${AI_SUITE_DIR}/monitoring"
    else
        rm -rf "${AI_SUITE_DIR}/monitoring" 2>/dev/null || true
    fi

    log_success "Stack monitoring supprimée"
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

    if $REMOVE; then
        remove_monitoring
        exit 0
    fi

    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Monitoring — Coolify AI Suite         ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    if $WITH_GRAFANA; then
        deploy_grafana_stack
        local ip
        ip=$(get_local_ip)
        echo ""
        echo -e "${GREEN}✓ Stack monitoring complète déployée !${NC}"
        echo ""
        echo -e "${BOLD}Accès :${NC}"
        echo -e "  • cAdvisor:  https://monitor.${TLD} ou http://${ip}:8080 (cAdvisor direct)"
        echo -e "  • Grafana:   https://grafana.${TLD} (admin/${GRAFANA_PASSWORD:-admin})"
        echo -e "  • Prometheus: https://prom.${TLD}"
        echo ""

        if [[ -n "${DOMAIN:-}" ]]; then
            echo -e "${YELLOW}Ajoutez ces enregistrements DNS :${NC}"
            echo -e "  A  monitor.${DOMAIN}  → ${ip}"
            echo -e "  A  grafana.${DOMAIN}  → ${ip}"
            echo -e "  A  prom.${DOMAIN}     → ${ip}"
        fi
    else
        deploy_cadvisor
        echo ""
        echo -e "${GREEN}✓ cAdvisor déployé !${NC}"
        echo -e "  Accès: https://monitor.${TLD} ou http://$(get_local_ip):8080"
        echo ""
        echo -e "  ${CYAN}Tip:${NC} Ajoutez --with-grafana pour Prometheus + Grafana"
    fi
    echo ""
}

main "$@"
