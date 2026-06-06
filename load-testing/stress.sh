#!/bin/bash

MINIKUBE_IP=$(minikube ip)
URL="http://$MINIKUBE_IP:30001/tickets/buy?movieId=1"

echo "Iniciando prueba de carga en $URL"
echo "Presiona Ctrl+C para detener."

while true; do
  curl -X POST -s $URL > /dev/null
  echo -n "."
  sleep 0.5
done
