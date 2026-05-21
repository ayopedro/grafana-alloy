# Alloy Observability Gateway

This repository contains a Grafana Alloy configuration for receiving telemetry locally and forwarding it to Grafana Cloud.

The current setup accepts:

- StatsD metrics over TCP on `9125`
- StatsD metrics over UDP on `9126`
- OTLP gRPC on `4317`
- OTLP HTTP on `4318`

It forwards:

- Metrics to Grafana Cloud Prometheus
- Logs to Grafana Cloud Loki
- Traces to Grafana Cloud Tempo

## Files

- `config.alloy`: main Alloy pipeline configuration
- `Dockerfile`: image definition based on `grafana/alloy:v1.14.1`
- `mapping-statsd.yaml`: StatsD mapping file included in the image

## Prerequisites

- Docker installed locally
- A `.env` file created from `.env.sample`

Create the local env file:

```bash
cp .env.sample .env
```

Then update `.env` with your Grafana Cloud values. The sample file contains:

```env
OTLP_METRICS_URL=https://prometheus-prod-xx.grafana.net/api/prom/push
OTLP_LOGS_URL=https://logs-prod-xxx.grafana.net/loki/api/v1/push
OTLP_TRACES_URL=tempo-prod-xx.grafana.net:443
GRAFANA_PASSWORD=your-grafana-cloud-token
```

Variable usage:

- `OTLP_METRICS_URL`: full HTTPS Prometheus remote write endpoint for metrics
- `OTLP_LOGS_URL`: full HTTPS Loki push endpoint for logs
- `OTLP_TRACES_URL`: Tempo OTLP gRPC endpoint in `host:port` format
- `GRAFANA_PASSWORD`: Grafana Cloud token used by all exporters

The trace endpoint intentionally does not include `https://` because the OTLP exporter in `config.alloy` expects a gRPC `host:port` endpoint.

## Run with Docker

Use the published Alloy image and mount the local configuration file:

```bash
docker run \
  --rm \
  -v "$PWD/config.alloy:/etc/alloy/config.alloy" \
  --env-file "$PWD/.env" \
  -p 12345:12345 \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 9125:9125/tcp \
  -p 9126:9126/udp \
  grafana/alloy:latest \
  run \
    --server.http.listen-addr=0.0.0.0:12345 \
    --storage.path=/var/lib/alloy/data \
    /etc/alloy/config.alloy
```

The Alloy UI and HTTP server will be available at `http://localhost:12345`.

## Run with the Local Dockerfile

If you want to use the repository image instead of bind-mounting the config:

```bash
docker build -t local/alloy-gateway .

docker run \
  --rm \
  --env-file "$PWD/.env" \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 9125:9125/tcp \
  -p 9126:9126/udp \
  local/alloy-gateway \
  --server.http.listen-addr=0.0.0.0:12345 \
  /etc/alloy/config.alloy
```

If you want the Alloy UI exposed in this mode, also publish port `12345`.

## Configuration Notes

- `config.alloy` reads endpoints from environment variables instead of hardcoded URLs.
- Metrics use `OTLP_METRICS_URL`, logs use `OTLP_LOGS_URL`, and traces use `OTLP_TRACES_URL`.
- The shared secret is read from `GRAFANA_PASSWORD` via `sys.env("GRAFANA_PASSWORD")`.
- If this repository is reused for another environment, update the endpoint variables in `.env` and any Grafana Cloud usernames in `config.alloy`.

## Telemetry Flow

1. Alloy receives StatsD and OTLP traffic locally.
2. StatsD metrics are exposed through the embedded StatsD exporter and scraped every `10s`.
3. OTLP signals are batched and forwarded to Grafana Cloud.

## Quick Checks

- Open `http://localhost:12345` to confirm Alloy is running.
- Send OTLP telemetry to `localhost:4317` or `localhost:4318`.
- Send StatsD metrics to `localhost:9125` or `localhost:9126`.
