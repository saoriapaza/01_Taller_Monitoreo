#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

NAMESPACE="cinema-system"
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
TICKET_SALES_URL="http://${MINIKUBE_IP}:30001"

case "${1:-status}" in
    "enable")
        DELAY=${2:-2000}
        echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  💥 CASUÍSTICA 4: EL SERVICIO LENTO             ║${NC}"
        echo -e "${RED}║  Inyectando delay de ${DELAY}ms en movie-catalog     ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        
        kubectl set env deployment/movie-catalog DELAY_MS="${DELAY}" -n "${NAMESPACE}"

        echo -e "${YELLOW}⏳ Esperando que el pod se reinicie con el nuevo delay...${NC}"
        kubectl rollout status deployment/movie-catalog -n "${NAMESPACE}" --timeout=60s

        echo ""
        echo -e "${RED}💥 CHAOS ACTIVO — movie-catalog tiene ${DELAY}ms de delay${NC}"
        echo ""
        echo "Para generar tráfico y ver los timeouts:"
        echo -e "${CYAN}  for i in {1..20}; do curl -s -X POST ${TICKET_SALES_URL}/tickets/buy?movieId=1; echo; sleep 1; done${NC}"
        ;;

    "disable")
        echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ DESACTIVANDO CHAOS — Volviendo a normal     ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
        echo ""

        kubectl set env deployment/movie-catalog DELAY_MS=0 -n "${NAMESPACE}"
        kubectl rollout status deployment/movie-catalog -n "${NAMESPACE}" --timeout=60s

        echo ""
        echo -e "${GREEN}✅ movie-catalog vuelve a comportamiento normal${NC}"
        ;;

    "status")
        echo -e "${CYAN}Estado actual de chaos:${NC}"
        kubectl get deployment movie-catalog -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].env}'
        echo ""
        ;;

    *)
        echo "Uso: $0 [enable|disable|status] [delay_ms]"
        ;;
esac
