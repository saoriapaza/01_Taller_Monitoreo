#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
TICKET_SALES_URL="http://${MINIKUBE_IP}:30001"

run_load_storm() {
    local iterations=${1:-500}
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  💥 CASUÍSTICA: TORMENTA DE REQUESTS            ║${NC}"
    echo -e "${RED}║  Generando ${iterations} requests concurrentes           ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Presiona ENTER para iniciar la tormenta... " -r

    echo -e "${RED}🌊 ¡INICIANDO TORMENTA DE REQUESTS!${NC}"
    
    local WAVE_SIZE=50
    local sent=0

    while (( sent < iterations )); do
        local this_wave=$WAVE_SIZE
        if (( sent + this_wave > iterations )); then
            this_wave=$(( iterations - sent ))
        fi

        for j in $(seq 1 "$this_wave"); do
            (
                HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${TICKET_SALES_URL}/tickets/buy?movieId=1" --max-time 5)
                if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
                    echo -ne "${GREEN}.${NC}"
                else
                    echo -ne "${RED}x${NC}"
                fi
            ) &
        done

        sent=$(( sent + this_wave ))
        wait
        echo " [$sent/$iterations] — $(date +%H:%M:%S)"
    done

    echo ""
    echo -e "${GREEN}✅ Tormenta completada.${NC}"
}

run_orders() {
    local count=${1:-20}
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  🛒 COMPRANDO ${count} TICKETS                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    for i in $(seq 1 "$count"); do
        RESPONSE=$(curl -s -X POST "${TICKET_SALES_URL}/tickets/buy?movieId=1")
        echo -e "  Compra ${i} → Completada"
        sleep 0.3
    done

    echo ""
    echo -e "${GREEN}✅ ${count} tickets comprados${NC}"
}

show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   🧪 SCRIPTS DE CASUÍSTICAS — Taller K8s              ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Opciones disponibles:"
    echo "  [load]    Tormenta de Requests (activa HPA si está configurado)"
    echo "  [orders]  Crear compras reales de tickets (tráfico normal)"
    echo ""
    echo "  Uso: bash load-testing/stress-test.sh <opción> [iteraciones]"
    echo ""
}

COMMAND=${1:-"menu"}
ITERATIONS=${2:-50}

case "$COMMAND" in
    "load")    run_load_storm "$ITERATIONS" ;;
    "orders")  run_orders "$ITERATIONS" ;;
    *)         show_menu ;;
esac
