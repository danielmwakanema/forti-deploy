# Forti Deploy

This repository contains configuration for deploying [Forti](github.com/metno/forti) using Docker Compose. It brings up the core services — `rawdataforecaster`, `correctedforecaster`, and `jsonfrontend` — using local forecast data.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose support
- Local forecast data (see [Preparing data](#preparing-data) below)

## Preparing data

Forecast data can be produced using [forti-prep](https://github.com/metno/forti-prep), a companion tool that downloads and post-processes the input datasets into the format expected by Forti.

By default, the Compose setup expects forecast data to be available at `../data/forecast` (relative to this repository). You can override this with the `FORECAST_DATA_PATH` environment variable.

## Services

| Service | Description | Default port |
|---|---|---|
| `caddy` | Reverse proxy with automatic HTTPS and SSL termination | `80`, `443` |
| `rawdataforecaster` | Serves forecast data over gRPC from a local directory | Internal only |
| `correctedforecaster` | Post-processes forecast data and re-exposes it over gRPC | Internal only |
| `jsonfrontend` | REST API that serves point forecast timeseries as JSON | Internal only (proxied via Caddy) |
| `healthz` | Health monitoring service that runs integration tests | Internal only (proxied via Caddy) |
| `prometheus` | Metrics collection and monitoring | `9091` (web UI) |

`correctedforecaster` is optional and must be enabled via a Docker Compose [profile](#profiles).

## Usage

Build and start the base services:

```bash
docker compose up --build
```

Test that the API is responding:

```bash
curl 'http://localhost/forecast.json?lat=59&lon=11'
```

By default, the reverse proxy listens on port 80 and forwards requests to `jsonfrontend`.

### Health monitoring

The `healthz` service continuously runs integration tests against `jsonfrontend` and exposes the results via HTTP:

```bash
# Simple health status (returns 200 OK if healthy, 503 if not)
curl http://localhost/healthz

# Detailed health status (JSON)
curl http://localhost/healthz/full
```

The health check configuration is in `healthz.config.json` and can be customized to test different locations and parameters.

### Monitoring with Prometheus

Prometheus is included for monitoring service metrics. Access the Prometheus web UI at:

```bash
http://localhost:9091
```

Prometheus automatically scrapes metrics from:
- **`jsonfrontend`** — REST API metrics (request duration, gzip usage, error counters)
- **`rawdataforecaster`** — gRPC service metrics (area requests, grid distances, dataset versions)
- **`caddy`** — Reverse proxy metrics (HTTP requests, response codes, TLS handshakes)
- **`prometheus`** — Self-monitoring metrics

The configuration is in `prometheus.yml`. Metrics are retained for 15 days by default.

Some useful metrics queries:

**jsonfrontend:**
- Request duration: `forti_jsonfrontend_total_processing_duration_seconds`
- Upstream processing time: `forti_jsonfrontend_upstream_processing_duration_seconds`
- Requests outside coverage: `forti_jsonfrontend_outside_all_grids`
- Gzipped responses: `forti_jsonfrontend_responses_with_gzip`

**rawdataforecaster:**
- Area request counts: `forti_requested_areas_total`
- Distance to grid point: `forti_distance_to_selected_grid_point`
- Active dataset version: `forti_active_latest`
- Dataset update time: `forti_active_updated`
- gRPC request duration: `grpc_server_handling_seconds`

**caddy:**
- HTTP requests: `caddy_http_requests_total`
- Response status: `caddy_http_response_status_count`

### Enabling correctedforecaster

`correctedforecaster` is disabled by default. To enable it, set both variables in your `.env` file:

```bash
COMPOSE_PROFILES=corrected
JSONFRONTEND_UPSTREAM=correctedforecaster:5051
```

Both need to change together: `COMPOSE_PROFILES` starts the container, and `JSONFRONTEND_UPSTREAM` points `jsonfrontend` at it. Leave `COMPOSE_PROFILES` empty (or unset) to run without correction.

## Reverse proxy and HTTPS

All external traffic goes through [Caddy](https://caddyserver.com/), which provides:

- **SSL termination** with automatic HTTPS certificate provisioning
- **Extensibility** for adding other endpoints
- **Access logging** in JSON format

### Local development (HTTP only)

By default, Caddy runs in HTTP mode on `localhost:80`. No additional configuration needed.

### Production deployment with HTTPS

Set the `DOMAIN` environment variable to enable automatic HTTPS:

```bash
DOMAIN=forti.example.com docker compose up
```

Caddy will automatically obtain and renew Let's Encrypt certificates. Make sure:

1. Port 443 is accessible from the internet
2. DNS for your domain points to the server
3. Caddy can write to its data volume (handled automatically by Docker)

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DOMAIN` | `localhost` | Domain name for automatic HTTPS (e.g., `forti.example.com`). Leave as `localhost` for local HTTP. |
| `HTTP_PORT` | `80` | HTTP port for Caddy |
| `HTTPS_PORT` | `443` | HTTPS port for Caddy (also HTTP/3 over UDP) |
| `PROMETHEUS_PORT` | `9091` | Prometheus web UI port |
| `FORECAST_DATA_PATH` | `../data/forecast` | Path to the local forecast data directory |
| `TOPOGRAPHY_DATA_PATH` | `../data/topography` | Path to the local topography data directory (used by `correctedforecaster`) |
| `JSONFRONTEND_UPSTREAM` | `rawdataforecaster:5052` | gRPC upstream address for `jsonfrontend` |

These can be set in a `.env` file in the repository root (`.env` is gitignored). Copy `.env.example` as a starting point:

```bash
cp .env.example .env
```

## Configuration

`rawdataforecaster.config.json` configures how `rawdataforecaster` reads forecast data:

```json
{
  "source": {
    "bucket": "file:///data/forecast"
  },
  "areas": ["meps"],
  "loader": {
    "type": "blob"
  }
}
```

- **`source.bucket`** — points to the mounted forecast data directory inside the container.
- **`areas`** — list of forecast areas to load (e.g. `meps`).
- **`loader.type`** — `"blob"` streams data on demand rather than loading everything into memory. Keep this as `"blob"` unless you have a specific reason to change it.
