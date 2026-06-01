# Claude Container

A batteries-included Docker container for running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [GSD Pi](https://www.npmjs.com/package/gsd-pi) as an SSH-accessible DevOps workstation. Access it from any terminal via SSH or from a browser with [WebSSH2](https://github.com/billchurch/webssh2).

**Docker Hub:** [`dgshue/claude-container`](https://hub.docker.com/r/dgshue/claude-container)

## What's Inside

| Category | Tools |
|----------|-------|
| **AI Agents** | Claude Code, GSD Pi, mcporter (MCP runtime) |
| **Languages** | Node.js 22, Python 3, PowerShell, Bash |
| **Cloud & Infra** | Terraform, kubectl, Helm, Azure CLI (all extensions), Docker CLI + Compose |
| **DevOps** | GitHub CLI, Trivy, hadolint, gitleaks |
| **Browsers** | Google Chrome, Chromium, Playwright |
| **Editors & Utils** | vim, nano, tmux, jq, httpie, curl, wget, rsync |
| **Access** | OpenSSH server, sudo-enabled user |

## Quick Start

### Docker Compose (Recommended)

```bash
# Clone and configure
git clone https://github.com/dgshue/claude-container.git
cd claude-container/example
cp .env.example .env        # Edit .env — set SSH_PASSWORD at minimum

# Start the container
docker compose up -d

# Connect via SSH
ssh claude@localhost -p 2222
```

### Docker Run

```bash
docker run -d --name claude-code \
  -p 2222:22 \
  -e SSH_USER=claude \
  -e SSH_PASSWORD=yourpassword \
  -v $(pwd)/workspace:/workspace \
  -v $(pwd)/claude-config:/claude \
  -e CLAUDE_CONFIG_DIR=/claude \
  dgshue/claude-container:latest

# Connect
ssh claude@localhost -p 2222
```

### Browser Access with WebSSH2

For browser-based terminal access, add WebSSH2 alongside the container:

```yaml
services:
  claude-code:
    image: dgshue/claude-container:latest
    # ... (see example/compose.yml)

  webssh2:
    image: billchurch/webssh2:latest
    ports:
      - "8080:2222"
```

Then open `http://localhost:8080/ssh/host/claude-code` in your browser.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_USER` | `claude` | SSH username |
| `SSH_PASSWORD` | `claude` | SSH password (**change this**) |
| `CLAUDE_CONFIG_DIR` | `/claude` | Claude Code config/credentials directory |
| `BRAVE_API_KEY` | _(empty)_ | Brave Search API key (convenience shortcut) |
| `MCP_SERVERS` | _(empty)_ | Inline JSON string with MCP server definitions |
| `MCP_SERVERS_FILE` | _(empty)_ | Path to a mounted JSON file with MCP servers |
| `MCP_FORCE_CONFIG` | `false` | Set to `true` to overwrite `settings.json` on restart |
| `PUID` | `1000` | Container user UID |
| `PGID` | `1000` | Container user GID |

### MCP Server Configuration

MCP servers are configured from three sources, merged in order (later sources win on name collisions):

1. **`BRAVE_API_KEY`** — convenience shortcut that adds the `brave-search` server
2. **`MCP_SERVERS_FILE`** — path to a mounted JSON file
3. **`MCP_SERVERS`** — inline JSON string

The entrypoint writes a merged `settings.json` to `CLAUDE_CONFIG_DIR`. If `settings.json` already exists, it is **not overwritten** unless `MCP_FORCE_CONFIG=true`.

#### Option A: Mount a JSON file

Create a `mcp-servers.json` file (see [`example/mcp-servers.json.example`](example/mcp-servers.json.example)):

```json
{
  "memory": {
    "command": "npx",
    "args": ["-y", "@anthropic-ai/claude-code-mcp-server-memory"]
  },
  "brave-search": {
    "command": "npx",
    "args": ["-y", "@anthropic-ai/claude-code-mcp-server-brave-search"],
    "env": { "BRAVE_API_KEY": "your-key" }
  }
}
```

Then in `compose.yml`:

```yaml
services:
  claude-code:
    environment:
      MCP_SERVERS_FILE: /mcp/servers.json
    volumes:
      - ./mcp-servers.json:/mcp/servers.json:ro
```

#### Option B: Inline JSON

For simple setups, pass the config directly:

```yaml
services:
  claude-code:
    environment:
      MCP_SERVERS: |
        {
          "memory": {
            "command": "npx",
            "args": ["-y", "@anthropic-ai/claude-code-mcp-server-memory"]
          }
        }
```

#### Option C: Combine sources

All three sources merge together. For example, use `BRAVE_API_KEY` for the search server and a file for everything else:

```yaml
services:
  claude-code:
    environment:
      BRAVE_API_KEY: ${BRAVE_API_KEY}
      MCP_SERVERS_FILE: /mcp/servers.json
    volumes:
      - ./mcp-servers.json:/mcp/servers.json:ro
```

Both JSON formats are accepted — a bare object `{...}` or wrapped as `{"mcpServers": {...}}`.

### Volumes

| Mount Point | Purpose |
|-------------|---------|
| `/workspace` | Your working directory — projects, repos, code |
| `/claude` | Claude Code credentials and settings (persists auth) |
| `/home/claude` | User home directory (shell history, dotfiles) |
| `/var/run/docker.sock` | _(optional)_ Docker-in-Docker access |

### First-Time Authentication

On first SSH login, run `claude` to start Claude Code. You'll be prompted to authenticate:

1. Choose your terminal color scheme
2. Select login method (Subscription or Console)
3. Open the provided URL in your browser to generate a token
4. Paste the token into the prompt

Credentials are saved to `/claude` and persist across container restarts.

## Nightly Auto-Updates

This container is automatically rebuilt every night at 3 AM UTC. The nightly workflow:

1. **Checks** the latest versions of all pinned packages (GitHub releases + npm)
2. **Updates** the Dockerfile with new versions
3. **Bumps** the container version (semver patch increment)
4. **Builds and pushes** to Docker Hub with `:latest`, `:nightly`, and `:X.Y.Z` tags
5. **Creates a GitHub Release** with detailed changelogs

Tracked packages: Terraform, kubectl, Helm, gosu, hadolint, Trivy, gitleaks, Claude Code, GSD Pi, mcporter, Playwright.

If no updates are found, no build runs (saves CI minutes).

### Pulling Updates

```bash
docker pull dgshue/claude-container:latest
docker compose up -d   # recreates with new image
```

## Image Tags

| Tag | Description |
|-----|-------------|
| `latest` | Most recent build (push to main or nightly) |
| `nightly` | Most recent nightly auto-update build |
| `X.Y.Z` | Specific version (e.g. `2.0.1`) |

## Project Structure

```
claude-container/
├── claude-code/
│   ├── Dockerfile          # Main container definition
│   ├── entrypoint.sh       # SSH + user setup + MCP config
│   └── mcp-settings.json   # Brave Search MCP template
├── example/
│   ├── compose.yml              # Ready-to-use Docker Compose
│   ├── .env.example             # Environment variable template
│   └── mcp-servers.json.example # MCP server config template
└── .github/
    ├── workflows/
    │   ├── build.yml       # Build on push to main
    │   └── nightly.yml     # Nightly version check + build
    └── scripts/
        ├── check-updates.sh    # Resolves latest package versions
        ├── apply-updates.sh    # Patches the Dockerfile
        └── bump-version.sh     # Increments semver tag
```

## Credits

Originally forked from [nezhar/claude-container](https://github.com/nezhar/claude-container). This project has since diverged significantly — rebuilt as an SSH-accessible DevOps workstation with nightly auto-updates, expanded tooling, and a different operational model.

## License

[MIT](LICENSE)
