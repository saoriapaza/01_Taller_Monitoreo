#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  🧹 TEARDOWN — Limpiando entorno del taller     ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
echo ""

OPTION=${1:-"partial"}

echo -e "${YELLOW}[1/5] Deteniendo port-forwards activos...${NC}"
pkill -f "kubectl port-forward" 2>/dev/null && echo "  Port-forwards detenidos" || echo "  No había port-forwards activos"
sleep 1

case "$OPTION" in
    "full")
        echo -e "${YELLOW}⚠️  TEARDOWN COMPLETO: eliminando Minikube entero${NC}"
        read -r -p "¿Estás seguro? Esto borra TODO Minikube (yes/no): " CONFIRM
        if [ "$CONFIRM" = "yes" ]; then
            minikube delete
            echo -e "${GREEN}✅ Minikube eliminado completamente${NC}"
        else
            echo "Cancelado."
            exit 0
        fi
        ;;

    "partial"|*)
        echo -e "${YELLOW}[2/5] Reseteando casuísticas activas...${NC}"
        kubectl set env deployment/movie-catalog DELAY_MS=0 -n cinema-system 2>/dev/null && echo "  Chaos delay reseteado a 0ms" || true

        echo -e "${YELLOW}[3/5] Eliminando microservicios...${NC}"
        kubectl delete -f k8s/movie-catalog/ --ignore-not-found 2>/dev/null || true
        kubectl delete -f k8s/ticket-sales/ --ignore-not-found 2>/dev/null || true
        kubectl delete -f k8s/monitoring/ --ignore-not-found 2>/dev/null || true
        echo "  Microservicios eliminados"

        echo -e "${YELLOW}[4/5] Desinstalando stack de monitoreo (Helm)...${NC}"
        helm uninstall prometheus -n monitoring 2>/dev/null \
            && echo "  Helm release 'prometheus' eliminado" \
            || echo "  (release 'prometheus' no encontrado, continuando)"

        echo -e "${YELLOW}[5/5] Eliminando namespaces...${NC}"
        kubectl delete namespace cinema-system --ignore-not-found 2>/dev/null || true
        kubectl delete namespace monitoring --ignore-not-found 2>/dev/null || true
        echo "  Namespaces eliminados"

        echo ""
        echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✅ Entorno limpio.${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  Para reinstalar desde cero:"
        echo -e "  ${CYAN}bash scripts/setup.sh${NC}"
        echo ""
        ;;
esac
