# Shared Alloy Observability Gateway

A shared, authenticated OTLP gateway for applications on any hosting platform. Each app pushes telemetry
with its own ingestion credentials; Alloy forwards traces, logs and metrics to
Grafana Cloud using a separate Cloud token.

```text
Apps → HTTPS + app credentials → Alloy :4318 → Grafana Cloud OTLP
```

## Configuration

Copy `.env.sample` to `.env` for local use. On your hosting platform, set these
container environment variables:

| Variable | Purpose |
| --- | --- |
| `GRAFANA_OTLP_ENDPOINT` | Exact HTTPS base URL from the Grafana Cloud OpenTelemetry tile, normally ending in `/otlp` |
| `GRAFANA_OTLP_USERNAME` | OTLP instance ID from that tile |
| `GRAFANA_PASSWORD` | Cloud token with metrics, logs and traces write permissions |
| `ALLOY_INGESTION_HTPASSWD` | One bcrypt htpasswd entry per app, separated by actual newlines |
| `PORT` | Optional hosting-platform setting: `4318`, matching the fixed OTLP HTTP receiver port; Alloy does not read this variable |

`OTLP_METRICS_URL`, `GRAFANA_METRICS_USERNAME`, `OTLP_LOGS_URL` and
`OTLP_TRACES_URL` are no longer used. StatsD ingestion has been removed. The unified exporter
appends each signal's `/v1/*` path to `GRAFANA_OTLP_ENDPOINT` automatically.
The startup script refuses to start when required variables are missing.

Generate an app entry interactively, avoiding a password in shell history:

```bash
htpasswd -nB the-bridge-26
```

If `htpasswd` is unavailable locally, use the Apache image:

```bash
docker run --rm -it --entrypoint htpasswd httpd:2.4-alpine -nB the-bridge-26
```

Paste the complete `username:$2y$...` output into `ALLOY_INGESTION_HTPASSWD`.
Repeat with a different username and password for every app. In your hosting
platform's secret settings, use actual multiline variable content. In local `.env`, use a single-quoted multiline
value so bcrypt dollar signs stay literal. Restart Alloy after changing entries.
These credentials permit ingestion into the same Grafana stack; they do not
provide tenant isolation or enforce an app's claimed `service.name`.

### Multiple apps

Generate one entry for each app, using a separate password:

```bash
htpasswd -nB the-bridge-26
htpasswd -nB another-app
```

Store both complete output lines in the gateway's `ALLOY_INGESTION_HTPASSWD`:

```text
the-bridge-26:$2y$...hash-for-the-first-app...
another-app:$2y$...hash-for-the-second-app...
```

Each app uses the same gateway endpoint but its own username and original password
in its authorization header. Authentication happens on every export without a
login flow. Removing an entry and restarting Alloy revokes those credentials;
other entries continue to work. Keep Grafana Cloud credentials only on the gateway.

## Deploy the gateway

1. Build the root Dockerfile and run its image on your container hosting platform.
   Use the image's default entrypoint so credential checks and Alloy startup run.
2. Set the environment variables above through the platform's secret settings.
3. Mount persistent storage at `/var/lib/alloy/data`.
4. Route a public HTTPS endpoint through your platform's ingress or a reverse
   proxy to the OTLP HTTP receiver on **port `4318`**. Terminate TLS at that ingress.
5. Start with one replica using that storage. Keep the gateway running continuously.
   Each additional replica needs independent storage; do not share queue files.
6. Keep management port `12345` and OTLP gRPC `4317` private.

The receiver listens on IPv6 wildcard addresses for dual-stack container
networking. Ensure your host supports IPv6 and accepts IPv4-mapped connections,
or adapt the listener addresses to the host's network configuration. Set a memory
budget with headroom above the `256MiB` OTLP memory-limiter threshold (start around
512 MiB and watch actual usage); this limiter does not cap total process RSS.

The OTLP receiver has no readiness health endpoint. Alloy's private management
server exposes `/-/ready`, `/-/healthy`, `/metrics` and the UI on port `12345`.
Configure health checks against that port where supported, and monitor export
failures, queue utilization and disk usage. Keep the public endpoint on port `4318`.

Apps with access to the gateway's private network can use its private HTTP address
with authentication. Apps elsewhere use the authenticated public HTTPS endpoint.
Private network reachability depends on the hosting platform's isolation rules.

## Configure apps

For each instrumented app, set server-side runtime variables (HTTP OTLP example):

```env
OTEL_SERVICE_NAME=the-bridge-26
OTEL_EXPORTER_OTLP_ENDPOINT=https://<your-alloy-domain>
OTEL_EXPORTER_OTLP_HEADERS="Authorization=Basic%20<base64-of-app-username-colon-password>"
OTEL_RESOURCE_ATTRIBUTES="deployment.environment.name=production,service.namespace=personal"
```

Use the app's original password here, not its bcrypt hash or the Grafana Cloud
token. The endpoint is the domain root, without `/otlp` or `/v1/traces`, because
this receiver serves `/v1/traces`, `/v1/metrics` and `/v1/logs`. Restart each app
and give it a distinct service name. Apps on the gateway's private network can
instead use `http://<alloy-private-hostname>:4318` with the same authentication header.

## Local Docker

```bash
docker build -t local/alloy-gateway .
docker run --rm --name alloy-gateway \
  --env-file .env \
  -p 127.0.0.1:4318:4318 \
  -p 127.0.0.1:12345:12345 \
  -v alloy-data:/var/lib/alloy/data \
  local/alloy-gateway
```

The management UI is at http://localhost:12345. To test gRPC locally, also publish
port `4317` on `127.0.0.1`. The Dockerfile pins Alloy v1.20.0.

Validate without starting receivers or sending telemetry (requires configured env):

```bash
docker run --rm --env-file .env --entrypoint /bin/alloy \
  local/alloy-gateway validate --stability.level=public-preview /etc/alloy/config.alloy
```

An unauthenticated request must be rejected:

```bash
curl -i -X POST http://localhost:4318/v1/traces \
  -H 'Content-Type: application/json' --data '{"resourceSpans":[]}'
```

Expect `401`. Retry with `curl -u the-bridge-26` to enter the password
interactively; an empty valid request should return `200`. This checks receiver
authentication, not Cloud delivery. Send real app traffic and verify the service
in Grafana Tempo, its metrics in Mimir and error logs in Loki.

## Buffering and compatibility

OTLP signals enter a bounded file-backed exporter queue **before** batching.
Queues are limited to 1000 requests per signal, retry retryable export failures
with backoff, and persist under `/var/lib/alloy/data/otlp-queue`. A mounted volume
allows queued data to survive replacement deployments. Monitor volume capacity.

The file-storage component is public preview, so startup and validation explicitly
use `--stability.level=public-preview`. Pin the image and validate upgrades.
Persistence does not guarantee lossless delivery: full queues, disk exhaustion,
permanent export errors, upstream app buffer loss and outage during redeployment
can still lose telemetry. Export retries are unlimited in duration for retryable
errors, but queue capacity remains bounded. This gateway does not add redaction
rules; tailor those to your apps before sending sensitive attributes.

References: [Alloy authentication](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.auth.basic/),
[OTLP HTTP exporter](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.otlphttp/),
[file storage](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.storage.file/),
[Grafana Cloud OTLP setup](https://grafana.com/docs/grafana-cloud/send-data/otlp/send-data-otlp/).
