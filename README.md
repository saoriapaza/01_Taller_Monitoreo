# Sistema de Cines - Microservicios en Kubernetes

Este repositorio contiene la solución completa para la tarea de Microservicios Java con Monitoreo en Kubernetes.

## Arquitectura

- **Servicio A (Movie Catalog):** Administra el catálogo de películas y sus asientos disponibles. Expone un puerto HTTP 8080.
  - Endpoints (4): `GET /movies`, `GET /movies/{id}`, `POST /movies/{id}/reserve`, `POST /movies`
  - Métricas (4): `movies.search.count` (Counter), `movies.reservation.time` (Timer), `movies.seats.available` (Gauge), `movies.artificial.delay` (Gauge).
- **Servicio B (Ticket Sales):** Permite a los usuarios comprar entradas. Se comunica vía HTTP WebClient con Movie Catalog. Expone un puerto HTTP 8081.
  - Endpoints (4): `GET /tickets`, `POST /tickets/buy`, `GET /tickets/{id}`, `DELETE /tickets/{id}`
  - Métricas (4): `tickets.sales.success` (Counter), `tickets.sales.failure` (Counter), `tickets.sales.timeout` (Counter), `tickets.process.time` (Timer).
- Todo está monitoreado por Prometheus y visualizado en Grafana.

## Requisitos Previos
- Docker Desktop
- Minikube
- kubectl
- Helm

## Cómo Ejecutar el Proyecto (One-Click)

Ve a la carpeta de scripts y ejecuta el automatizador:
```bash
cd scripts
./setup.sh
```
*Este script verificará herramientas, levantará Minikube, instalará Helm, compilará las imágenes Docker locales y desplegará los manifiestos.*

### URLs de Acceso Rápido
Una vez finalizado el script, te mostrará las URLs (que usan la IP de Minikube):
- **Grafana:** `http://<MINIKUBE_IP>:32000` (Usuario: `saoriAdmin` / Password: `saori123`)
- **Prometheus:** `http://<MINIKUBE_IP>:32001`
- **Catálogo de Películas:** `http://<MINIKUBE_IP>:30000/movies`
- **Venta de Boletos:** `http://<MINIKUBE_IP>:30001/tickets/buy?movieId=1` (POST)

## Generación de Carga
Para ver métricas en Grafana, puedes generar tráfico ejecutando:
```bash
cd load-testing
./stress.sh
```

---

## 3 Casuísticas Implementadas

### Casuística 1 — El Servicio Caído
- **Contexto narrativo:** El servicio de catálogo de películas falla repentinamente y entra en `CrashLoopBackOff`, lo que interrumpe la venta de entradas.
- **Síntoma:** El usuario intenta comprar una entrada pero recibe un error 500 o 502 porque el Ticket Sales no puede alcanzar al Movie Catalog.
- **Activación:** `kubectl scale deployment movie-catalog --replicas=0 -n cinema-system` (o alterando la probe para que falle).
- **Diagnóstico:** En Prometheus la alerta `MovieCatalogDown` entra en estado `FIRING`. En Grafana, el panel de "Estado Movie Catalog" muestra 0.
- **Resolución:** `kubectl scale deployment movie-catalog --replicas=1 -n cinema-system`
- **Lección técnica:** Las Liveness probes detectan si el servicio está roto y Kubernetes intenta reiniciarlo, mientras que las métricas y alertas nos avisan que perdimos capacidad de cómputo.

### Casuística 2 — El Servicio Lento
- **Contexto narrativo:** La base de datos del Movie Catalog está saturada, causando demoras masivas.
- **Síntoma:** Al intentar comprar, la pantalla carga infinitamente o lanza un timeout.
- **Activación:** Inyectar un delay artificial cambiando el Deployment de `movie-catalog`.
  ```bash
  kubectl set env deployment/movie-catalog DELAY_MS=5000 -n cinema-system
  ```
- **Diagnóstico:** El panel "Latencia de Reserva" se dispara a >5000ms. La alerta `HighTicketSalesFailure` se activa debido a que Ticket Sales tiene un timeout estricto de 2 segundos.
- **Resolución:** `kubectl set env deployment/movie-catalog DELAY_MS=0 -n cinema-system`
- **Lección técnica:** La latencia en un servicio downstream se propaga hacia arriba. Un timeout bien configurado (como hicimos en el WebClient de Ticket Sales) protege al sistema de colapsar.

### Casuística 3 — Entradas Agotadas (Situación de Negocio)
- **Contexto narrativo:** Hay un estreno masivo y todas las entradas de todas las películas se venden.
- **Síntoma:** Los usuarios reciben un error HTTP 400 "Sold out" al intentar comprar.
- **Activación:** Correr el script `stress.sh` por varios minutos hasta que la métrica de `movies_seats_available` llegue a 0.
- **Diagnóstico:** En Grafana, el medidor de "Asientos Disponibles" baja progresivamente hasta 0. La alerta PromQL `MoviesSoldOut` se activa.
- **Resolución:** Recargar la base de datos (Reiniciar el pod de movie-catalog).
  ```bash
  kubectl rollout restart deployment movie-catalog -n cinema-system
  ```
- **Lección técnica:** Prometheus no solo sirve para medir CPU o memoria, sino que también nos permite observar en tiempo real el comportamiento del negocio (ej. el inventario total).
