#!/bin/bash

echo "Eliminando recursos de Kubernetes..."
kubectl delete -f ../k8s/ --ignore-not-found=true

echo "Desinstalando Prometheus..."
helm uninstall prometheus -n monitoring || true

if [ "$1" == "--all" ]; then
    echo "Eliminando cluster de Minikube..."
    minikube delete
else
    echo "Cluster de Minikube sigue activo. Usa '--all' para eliminarlo."
fi

echo "¡Teardown completado!"
