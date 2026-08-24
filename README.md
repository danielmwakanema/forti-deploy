# Deploy

This folder contains configuration for running Forti locally using Docker Compose. It brings up the core services — `rawdataforecaster`, `correctedforecaster`, and `jsonfrontend` — using local forecast data.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose support
- Local forecast data (see [Preparing data](#preparing-data) below)

## Preparing data

Forecast data can be produced using [forti-prep](https://github.com/metno/forti-prep), a companion tool that downloads and post-processes the input datasets into the format expected by Forti.

By default, the Compose setup expects forecast data to be available at `../data/forecast` (relative to this folder), which corresponds to `data/forecast/` in the repository root. You can override this with the `FORECAST_DATA_PATH` environment variable.

## Services

| Service | Description | Default port |
|---|---|---|
| `caddy` | Reverse proxy with automatic HTTPS and SSL termination | `80`, `443` |
| `rawdataforecaster` | Serves forecast data over gRPC from a local directory | Internal only |
| `correctedforecaster` | Post-processes forecast data and re-exposes it over gRPC | Internal only |
| `jsonfrontend` | REST API that serves point forecast timeseries as JSON | Internal only (proxied via Caddy) |

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
| `FORECAST_DATA_PATH` | `../data/forecast` | Path to the local forecast data directory |
| `TOPOGRAPHY_DATA_PATH` | `../data/topography` | Path to the local topography data directory (used by `correctedforecaster`) |
| `JSONFRONTEND_UPSTREAM` | `rawdataforecaster:5052` | gRPC upstream address for `jsonfrontend` |

These can be set in a `.env` file in this directory (`.env` is gitignored). Copy `.env.example` as a starting point:

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
