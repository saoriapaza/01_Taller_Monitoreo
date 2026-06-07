#!/bin/bash
set -e

echo "==========================================="
echo "   Iniciando Setup del Sistema de Cines    "
echo "==========================================="

echo "[0/7] Instalando herramientas..."
sudo apt-get update && sudo apt-get install -y docker.io curl git openjdk-17-jdk maven socat apt-transport-https

# Instalar kubectl si no existe
if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
fi

# Instalar minikube si no existe
if ! command -v minikube >/dev/null 2>&1; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64
fi

# Instalar helm si no existe
if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm -f get_helm.sh
fi

sudo systemctl start docker || true
sudo systemctl enable docker || true

echo "[1/7] Validando herramientas..."
command -v minikube >/dev/null 2>&1 || { echo >&2 "Minikube no está instalado."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo >&2 "Kubectl no está instalado."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo >&2 "Helm no está instalado."; exit 1; }

echo "[2/7] Iniciando Minikube y Addons..."
# Ejecutar como usuario normal
minikube status | grep -q "Running" || minikube start --cpus=4 --memory=4096
minikube addons enable metrics-server

echo "[3/7] Instalando Prometheus y Grafana (Helm)..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -f ../k8s/monitoring/prometheus-values.yaml -n monitoring --create-namespace --wait

echo "[4/7] Construyendo imágenes de Docker..."
# Apuntar docker al daemon de minikube
eval $(minikube docker-env)

cd ../microservices/movie-catalog
mvn clean package -DskipTests
docker build -t movie-catalog:latest .

cd ../ticket-sales
mvn clean package -DskipTests
docker build -t ticket-sales:latest .
cd ../../scripts

echo "[5/7] Aplicando Manifiestos de Kubernetes..."
kubectl apply -f ../k8s/namespace.yaml
# Usamos las nuevas rutas donde fueron movidos los YAMLs
kubectl apply -f ../k8s/movie-catalog/movie-catalog.yaml
kubectl apply -f ../k8s/ticket-sales/ticket-sales.yaml
kubectl apply -f ../k8s/monitoring/servicemonitors.yaml
kubectl apply -f ../k8s/monitoring/alerting-rules.yaml

echo "[6/7] Importando Dashboard en Grafana..."
echo "Esperando a que Grafana esté listo..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=120s || true

# Port-forward temporal para la carga inicial del JSON por REST API
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring &
PF_PID=$!
sleep 5
DASHBOARD_PAYLOAD=$(cat ../k8s/monitoring/grafana-dashboard.json)
curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "{\"dashboard\": ${DASHBOARD_PAYLOAD}, \"overwrite\": true, \"folderId\": 0}" \
    "http://saoriAdmin:saori123@localhost:3000/api/dashboards/db" > /dev/null || true
kill $PF_PID 2>/dev/null || true

echo "[7/7] Esperando a que los pods estén listos..."
kubectl wait --for=condition=ready pod -l app=movie-catalog -n cinema-system --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=ticket-sales -n cinema-system --timeout=120s || true

echo "==========================================="
echo "¡Setup Completado Exitosamente!"
echo "==========================================="
echo "Iniciando socat para mapeo de puertos en EC2..."

sudo pkill -f "socat" 2>/dev/null || true

sudo socat TCP-LISTEN:32000,fork TCP:192.168.49.2:32000 &
sudo socat TCP-LISTEN:32001,fork TCP:192.168.49.2:32001 &
sudo socat TCP-LISTEN:30000,fork TCP:192.168.49.2:30000 &
sudo socat TCP-LISTEN:30001,fork TCP:192.168.49.2:30001 &

echo "==========================================="
echo "Los servicios están expuestos."
echo "Accede a tus servicios usando la IP pública de tu EC2 en los puertos:"
echo " - 30000: Movie Catalog API"
echo " - 30001: Ticket Sales API"
echo " - 32000: Grafana UI"
echo " - 32001: Prometheus UI"
echo "==========================================="
