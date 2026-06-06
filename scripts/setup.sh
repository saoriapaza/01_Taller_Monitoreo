#!/bin/bash
set -e

echo "==========================================="
echo "   Iniciando Setup del Sistema de Cines    "
echo "==========================================="

echo "[1/6] Validando herramientas..."
command -v minikube >/dev/null 2>&1 || { echo >&2 "Minikube no está instalado."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "Kubectl no está instalado."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo >&2 "Helm no está instalado."; exit 1; }

echo "[2/6] Iniciando Minikube y Addons..."
minikube status | grep -q "Running" || minikube start --cpus=4 --memory=4096
minikube addons enable metrics-server

echo "[3/6] Instalando Prometheus y Grafana (Helm)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -f ../k8s/values.yaml -n monitoring --create-namespace

echo "[4/6] Construyendo imágenes de Docker..."
# Apuntar docker al daemon de minikube
eval $(minikube docker-env)

cd ../microservices/movie-catalog
docker build -t movie-catalog:latest .

cd ../ticket-sales
docker build -t ticket-sales:latest .
cd ../../scripts

echo "[5/6] Aplicando Manifiestos de Kubernetes..."
kubectl apply -f ../k8s/namespace.yaml
kubectl apply -f ../k8s/movie-catalog.yaml
kubectl apply -f ../k8s/ticket-sales.yaml
kubectl apply -f ../k8s/servicemonitors.yaml
kubectl apply -f ../k8s/alerts.yaml

echo "[6/6] Esperando a que los pods estén listos..."
kubectl wait --for=condition=ready pod -l app=movie-catalog -n cinema-system --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=ticket-sales -n cinema-system --timeout=120s || true

MINIKUBE_IP=$(minikube ip)
echo "==========================================="
echo "¡Setup Completado Exitosamente!"
echo "Movie Catalog API: http://$MINIKUBE_IP:30000/movies"
echo "Ticket Sales API:  http://$MINIKUBE_IP:30001/tickets"
echo "Grafana UI:        http://$MINIKUBE_IP:32000 (saoriAdmin / saori123)"
echo "Prometheus UI:     http://$MINIKUBE_IP:32001"
echo "==========================================="
