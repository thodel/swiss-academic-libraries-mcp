# swiss-academic-libraries-mcp — MCP Server

An [MCP](https://modelcontextprotocol.io) server wrapping
[`swiss-academic-libraries-mcp`](https://github.com/malkreide/swiss-academic-libraries-mcp):
read-only access to Swiss discovery platforms and open-access scholarly resources —
Swisscovery, e-rara, e-periodica, e-manuscripta, OA legal literature, Crossref, and
arXiv — via 16 tools. No API key required.

This repo is the fleet-compatible Docker wrapper; the actual MCP implementation is a
third-party PyPI package maintained elsewhere.

## Architecture

```
swiss-academic-libraries-mcp (PyPI)  ──►  uvicorn (streamable HTTP)  ──►  :8005/mcp
```

The package ships no configuration file and takes only three flags:
`--http`, `--port`, `--host`. There is no `--http-path` flag, so the endpoint is always
served at the server root (`/mcp`). See [the gotcha below](#gotcha-no-http-path-flag)
before wiring this up behind a reverse proxy.

## Fleet port map

| Server | Port |
|--------|------|
| EOS / HGB Basel | 8000 |
| Königsfelden (kf_mcp) | 8001 |
| SSRQ | 8002 |
| HBLS | 8003 |
| HLS | 8004 |
| **swiss-academic-libraries-mcp** | **8005** |

## Prerequisites

```bash
uv --version   # or: curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Run locally (no Docker)

```bash
uvx swiss-academic-libraries-mcp --http --port 8005
```

First run downloads and caches the package; subsequent starts are instant.
`--host` defaults to `127.0.0.1` — pass `--host 0.0.0.0` to listen on all interfaces.

## Docker deployment

### Build

```bash
docker compose build
```

### Run

```bash
docker compose up -d
docker compose ps
```

Verify the container started cleanly:

```bash
docker logs swisslib-mcp 2>&1 | grep -i starting | tail -1
```

### Rebuild after package updates

```bash
docker compose build --pull && docker compose up -d
```

## Connect a client

### Claude Code

```bash
claude mcp add --transport http swisslib http://<server-ip>:8005/mcp -s user
```

`-s user` makes the server available in every project on this machine.
`claude mcp list` reports connection status.

### Claude Desktop, Cowork, claude.ai

Customize → Connectors → **+** → *Add custom connector*, paste the same URL.
These clients connect from Anthropic's cloud, not from your machine, so the server must
be reachable over the public internet.

### Project-scoped `.mcp.json`

```json
{
  "mcpServers": {
    "swisslib": {
      "type": "http",
      "url": "http://<server-ip>:8005/mcp"
    }
  }
}
```

## Available tools

| Tool | Description |
|------|-------------|
| `swisscovery_search(query, limit)` | Search Swisscovery by title/author/ISSN |
| `swisscovery_get(record_id)` | Fetch a single Swisscovery record |
| `erara_search(query, limit)` | Search e-rara (Swiss ETH/uni digitised books) |
| `erara_get(record_id)` | Fetch a single e-rara record |
| `eperiodica_search(query, limit)` | Search e-periodica (Swiss journals) |
| `eperiodica_get(record_id)` | Fetch a single e-periodica record |
| `emanuscripta_search(query, limit)` | Search e-manuscripta (Swiss manuscripts) |
| `emanuscripta_get(record_id)` | Fetch a single e-manuscripta record |
| `oa_legal_search(query, limit)` | Search OA legal literature |
| `oa_legal_get(record_id)` | Fetch a single OA legal record |
| `crossref_works(query, limit)` | Search Crossref by DOI, title, or author |
| `crossref_work(doi)` | Fetch a single Crossref work |
| `crossref_funder_works(funder_id, limit)` | Works for a Crossref funder |
| `arxiv_search(query, limit)` | Search arXiv by title/author/abstract |
| `arxiv_get(arxiv_id)` | Fetch a single arXiv record |
| `list_tools()` | Enumerate all available tools |

## Reverse proxy (nginx)

<a id="gotcha-no-http-path-flag"></a>

> **Gotcha: no `--http-path` flag.** All other fleet servers expose
> `--http-path` / `<NAME>_HTTP_PATH` so nginx can proxy a sub-path through unchanged.
> `swiss-academic-libraries-mcp` has no such flag — it only ever answers on `/mcp` at
> the server root. A naively copy-pasted no-rewrite `location` block (the pattern used
> for `kf_mcp` and siblings) will 404.

The nginx block must **rewrite** the path:

```nginx
server {
    listen 443 ssl;
    server_name tei.example.ch;

    location /mcp/swisslib/ {
        # Rewrite strips the location prefix; the app sees /mcp at root.
        rewrite ^/mcp/swisslib/(.*)$ /$1 break;
        proxy_pass         http://127.0.0.1:8005;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_set_header   Connection '';
        proxy_buffering    off;
        proxy_cache        off;
        proxy_read_timeout 3600s;
        chunked_transfer_encoding on;
    }
}
```

The public URL is `https://tei.example.ch/mcp/swisslib/` (trailing slash required).

## Verify the endpoint

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8005/mcp \
 -H 'Content-Type: application/json' \
 -H 'Accept: application/json, text/event-stream' \
 -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
```

`200` = live. Any other code indicates a problem (check the server is running, port is
correct, and no other service has claimed 8005).

## Configuration (optional environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `CROSSREF_MAILTO` | _(none)_ | Polite Crossref API usage — your email address |
| `ARXIV_DELAY` | _(none)_ | Seconds to wait between arXiv requests |
| `OA_LEGAL_LICENSE` | _(none)_ | Licence filter for OA legal searches |

None are required; all have sensible defaults.
