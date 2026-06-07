#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

PID_FILE="/tmp/taller-k8s-portforward.pids"
LOG_DIR="/tmp/taller-k8s-logs"
mkdir -p "$LOG_DIR"

detect_environment() {
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    else
        echo "linux"
    fi
}

ENV_TYPE=$(detect_environment)

if [[ "$ENV_TYPE" == "wsl" ]]; then
    BIND_ADDRESS="0.0.0.0"
    BROWSER_HOST="localhost"
else
    BIND_ADDRESS="127.0.0.1"
    BROWSER_HOST="localhost"
fi

GRAFANA_SVC="grafana|monitoring|prometheus-grafana|32000|80|📊 Grafana Dashboards"
PROMETHEUS_SVC="prometheus|monitoring|prometheus-kube-prometheus-prometheus|32001|9090|🔥 Prometheus"
MOVIE_SVC="movie-catalog|cinema-system|movie-catalog|30000|8080|🎬 movie-catalog"
TICKET_SVC="ticket-sales|cinema-system|ticket-sales|30001|8081|🎟️ ticket-sales"

ALL_SERVICES=("$GRAFANA_SVC" "$PROMETHEUS_SVC" "$MOVIE_SVC" "$TICKET_SVC")

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   🎓 TALLER: MONITOREO KUBERNETES                       ║"
    echo "║      Port-Forward Manager                               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Entorno detectado: ${YELLOW}${ENV_TYPE^^}${NC}"
    echo -e "  Bind address:      ${YELLOW}${BIND_ADDRESS}${NC}"
    echo ""
}

check_kubernetes() {
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}[ERROR] No se puede conectar al cluster de Kubernetes.${NC}"
        exit 1
    fi
}

kill_existing() {
    if [[ -f "$PID_FILE" ]]; then
        echo -e "${YELLOW}[INFO] Deteniendo port-forwards anteriores...${NC}"
        while IFS= read -r pid; do
            kill "$pid" 2>/dev/null && echo "  Detenido PID $pid" || true
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 1
}

wait_for_port() {
    local port=$1
    local name=$2
    local max_attempts=20
    local attempt=0

    while ! nc -z localhost "$port" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            return 1
        fi
        sleep 0.5
    done
    return 0
}

start_port_forward() {
    local config=$1
    IFS='|' read -r name namespace svc local_port remote_port description <<< "$config"

    if ! kubectl get svc "$svc" -n "$namespace" &>/dev/null; then
        echo -e "  ${YELLOW}[SKIP]${NC} $description — Service no encontrado"
        return 0
    fi

    local log_file="$LOG_DIR/${name}.log"
    echo -ne "  Iniciando $description (localhost:${local_port})... "

    kubectl port-forward "svc/${svc}" "${local_port}:${remote_port}" -n "$namespace" --address "$BIND_ADDRESS" > "$log_file" 2>&1 &
    local pid=$!
    echo "$pid" >> "$PID_FILE"

    if wait_for_port "$local_port" "$description"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}lento, puede tardar...${NC}"
    fi
}

show_urls() {
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🌐 SERVICIOS DISPONIBLES — Abre en tu navegador:${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  📊 Grafana           → ${CYAN}http://${BROWSER_HOST}:32000${NC}"
    echo -e "                         Usuario: ${YELLOW}saoriAdmin${NC}  Contraseña: ${YELLOW}saori123${NC}"
    echo ""
    echo -e "  🔥 Prometheus        → ${CYAN}http://${BROWSER_HOST}:32001${NC}"
    echo ""
    echo -e "  🎬 movie-catalog     → ${CYAN}http://${BROWSER_HOST}:30000/movies${NC}"
    echo ""
    echo -e "  🎟️ ticket-sales      → ${CYAN}http://${BROWSER_HOST}:30001/tickets${NC}"
    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${MAGENTA}💥 CASUÍSTICAS (en otra terminal):${NC}"
    echo -e "  bash load-testing/stress-test.sh load     # Tormenta de peticiones (HPA)"
    echo -e "  bash load-testing/stress-test.sh orders   # Tráfico normal de compras"
    echo -e "  bash load-testing/chaos-delay.sh enable   # Retardo en movie-catalog"
    echo ""
    echo -e "  Presiona ${RED}Ctrl+C${NC} para detener todos los port-forwards."
    echo ""
}

monitor_processes() {
    while true; do
        sleep 10
        local dead=false
        if [[ -f "$PID_FILE" ]]; then
            while IFS= read -r pid; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    dead=true
                fi
            done < "$PID_FILE"
        fi
        if [[ "$dead" == "true" ]]; then
            rm -f "$PID_FILE"
            touch "$PID_FILE"
            for svc_config in "${ALL_SERVICES[@]}"; do
                start_port_forward "$svc_config"
            done
        fi
    done
}

cleanup() {
    echo ""
    echo -e "${YELLOW}[INFO] Deteniendo todos los port-forwards...${NC}"
    kill_existing
    echo -e "${GREEN}[OK] Todos los port-forwards detenidos. ¡Hasta la próxima clase!${NC}"
    exit 0
}

COMMAND="${1:-start}"
case "$COMMAND" in
    "stop")
        kill_existing
        exit 0
        ;;
    "start"|*)
        print_banner
        check_kubernetes
        echo -e "${BLUE}[INFO] Iniciando port-forwards...${NC}"
        kill_existing
        touch "$PID_FILE"
        for svc_config in "${ALL_SERVICES[@]}"; do
            start_port_forward "$svc_config"
        done
        show_urls
        trap cleanup SIGINT SIGTERM
        monitor_processes
        ;;
esac
