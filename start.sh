#!/bin/sh
set -eu

# Fail closed rather than starting a public receiver without credentials.
: "${ALLOY_INGESTION_HTPASSWD:?Set htpasswd entries for app ingestion}"
: "${GRAFANA_OTLP_ENDPOINT:?Set the Grafana Cloud OTLP base URL}"
: "${GRAFANA_OTLP_USERNAME:?Set the Grafana Cloud OTLP instance ID}"
: "${GRAFANA_PASSWORD:?Set the Grafana Cloud write token}"
: "${OTLP_METRICS_URL:?Set the Prometheus remote-write URL for StatsD}"
: "${GRAFANA_METRICS_USERNAME:?Set the Prometheus instance ID for StatsD}"

exec /bin/alloy run \
  --stability.level=public-preview \
  --server.http.listen-addr='[::]:12345' \
  --storage.path=/var/lib/alloy/data \
  /etc/alloy/config.alloy "$@"
