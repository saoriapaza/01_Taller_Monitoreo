# Informe Técnico

## Parte A — Conceptos

**1. ¿Qué es Micrometer y por qué se usa en lugar de la librería directa de Prometheus?**
Micrometer es una fachada (facade) de métricas para aplicaciones Java (como el SLF4J pero para métricas). Se usa porque desacopla el código de la aplicación de la herramienta de monitoreo subyacente. En lugar de escribir código que solo entiende Prometheus, escribimos código para Micrometer, y este se encarga de traducirlo y exponerlo en el formato que Prometheus necesita. Si mañana cambiamos a Datadog o New Relic, no tocamos el código, solo cambiamos la dependencia.

**2. ¿Cuál es la diferencia entre Counter, Gauge y Timer? Da un ejemplo de cada uno tomado de tu código.**
- **Counter:** Solo puede ir hacia arriba (aumentar). Sirve para medir cosas que ocurren como "veces que se ejecutó algo". 
  - *Ejemplo en código:* `ticketSuccessCounter` que cuenta cuántos boletos se vendieron.
- **Gauge:** Puede subir y bajar. Mide un valor actual en un momento dado.
  - *Ejemplo en código:* `totalAvailableSeats`, que disminuye conforme se venden las entradas.
- **Timer:** Mide tanto el conteo de eventos como el tiempo total y el tiempo máximo que tardan en ejecutarse. Útil para medir latencias.
  - *Ejemplo en código:* `reservationTimer` que mide cuánto tardó el bloque `try-finally` al reservar un asiento en `MovieController.java`.

**3. ¿Qué es un ServiceMonitor y cómo sabe el Prometheus Operator qué monitorear?**
Es un recurso personalizado (CRD) introducido por Prometheus Operator. Describe un conjunto de *targets* (servicios) que Prometheus debe raspar para obtener métricas. El Operator sabe qué monitorear leyendo el campo `selector` del ServiceMonitor. Si los `matchLabels` coinciden con las etiquetas de un Kubernetes Service, el Operator reescribe dinámicamente el archivo de configuración de Prometheus para que vaya a ese Service a pedir las métricas.

**4. ¿Cuál es la diferencia entre liveness probe y readiness probe?**
- **Liveness Probe:** Responde a la pregunta "¿está el contenedor vivo?". Si falla, Kubernetes asume que el contenedor está bloqueado/roto, lo mata y lo reinicia (entra en CrashLoopBackOff si sigue fallando).
- **Readiness Probe:** Responde a la pregunta "¿está el contenedor listo para recibir tráfico?". Si falla (por ejemplo, porque la app está cargando configuraciones pesadas), Kubernetes NO lo mata, simplemente lo saca de la lista de endpoints del Service para que no le lleguen peticiones de los usuarios temporalmente.

**5. ¿Por qué es necesario apuntar Docker al daemon de Minikube antes de construir las imágenes?**
Porque Minikube corre su propio entorno Docker aislado dentro de su máquina virtual. Si usamos el Docker de nuestra PC (`docker build...`) la imagen se queda en nuestra PC host. Cuando Kubernetes intente desplegar el pod, buscará la imagen dentro de la máquina de Minikube (o en internet) y dará error `ImagePullBackOff` porque no existe ahí. Ejecutar `eval $(minikube docker-env)` vincula nuestra consola al Docker de Minikube para construir la imagen directamente allí adentro.

**6. ¿Qué ocurre si no configuras el selector de ServiceMonitors en el values.yaml del chart?**
Por defecto, el chart `kube-prometheus-stack` está configurado para que su instancia de Prometheus SOLO haga caso a los ServiceMonitors que tengan ciertas etiquetas específicas del chart (como `release: prometheus`). Si no configuramos `serviceMonitorSelectorNilUsesHelmValues: false` (o no ponemos las etiquetas correctas), Prometheus ignorará olímpicamente los ServiceMonitors que nosotros creamos, y los endpoints de nuestros microservicios jamás aparecerán en la pestaña `/targets`.

---

## Parte B — PromQL 

**1. Tasa de requests por minuto de tu Servicio B en los últimos 5 minutos**
```promql
rate(http_server_requests_seconds_count{application="ticket-sales"}[5m]) * 60
```

**2. Latencia p95 del endpoint más crítico de tu sistema**
(Endpoint: `/movies/{id}/reserve` de Movie Catalog)
```promql
histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket{uri="/movies/{id}/reserve"}[5m])) by (le))
```
*(Nota: Micrometer usa buckets para los Timers que permiten este cálculo).*

**3. Estado UP/DOWN de ambos servicios al mismo tiempo**
```promql
up{job=~"movie-catalog|ticket-sales"}
```

**4. Una query que responda una pregunta de negocio propia de tu dominio**
*Pregunta: ¿A qué ritmo se están agotando las entradas en general? (Asientos perdidos por minuto)*
```promql
rate(movies_seats_available[5m]) * -60
```
