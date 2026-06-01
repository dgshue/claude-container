#!/bin/bash
#
# Entrypoint script for Claude Code DevOps workstation
# Handles dynamic UID/GID mapping, SSH daemon, and MCP config
#

set -e

# Default to user 1000:1000 if not specified
USER_UID=${USER_UID:-1000}
USER_GID=${USER_GID:-1000}

# ── SSH user setup ────────────────────────────────────────────────────
setup_ssh_user() {
    local ssh_user="${SSH_USER:-claude}"
    local ssh_password="${SSH_PASSWORD:-claude}"

    # Create the SSH user if it doesn't already exist
    if ! id "$ssh_user" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$ssh_user"
    fi

    # Set password
    echo "${ssh_user}:${ssh_password}" | chpasswd

    # Add to sudo with NOPASSWD
    echo "${ssh_user} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${ssh_user}"
    chmod 0440 "/etc/sudoers.d/${ssh_user}"
}

# ── Start SSH daemon ─────────────────────────────────────────────────
start_sshd() {
    /usr/sbin/sshd
}

# ── Docker socket access ──────────────────────────────────────────────
setup_docker_socket() {
    local sock="/var/run/docker.sock"
    if [ -S "$sock" ]; then
        # Get the GID of the docker socket from the host
        local docker_gid
        docker_gid=$(stat -c '%g' "$sock")
        # Create a docker group with matching GID if it doesn't exist
        if ! getent group "$docker_gid" >/dev/null 2>&1; then
            groupadd -g "$docker_gid" docker 2>/dev/null || true
        fi
        local docker_group
        docker_group=$(getent group "$docker_gid" | cut -d: -f1)
        # Add the SSH user to the docker group
        local ssh_user="${SSH_USER:-claude}"
        usermod -aG "$docker_group" "$ssh_user" 2>/dev/null || true
    fi
}

# ── MCP config setup ─────────────────────────────────────────────────
#
# MCP servers can be configured from three sources (merged in order):
#   1. BRAVE_API_KEY env var        → adds brave-search server (convenience shortcut)
#   2. MCP_SERVERS_FILE env var     → path to a JSON file with mcpServers object
#   3. MCP_SERVERS env var          → inline JSON string with mcpServers object
#
# Later sources override earlier ones when server names collide.
# If settings.json already exists, MCP config is NOT overwritten unless
# MCP_FORCE_CONFIG=true is set.
#
setup_mcp_config() {
    local config_dir="${CLAUDE_CONFIG_DIR:-/claude}"
    local settings_file="${config_dir}/settings.json"

    # Check if any MCP configuration is provided
    local has_config=false
    [ -n "${BRAVE_API_KEY:-}" ] && has_config=true
    [ -n "${MCP_SERVERS_FILE:-}" ] && has_config=true
    [ -n "${MCP_SERVERS:-}" ] && has_config=true

    if [ "$has_config" = false ]; then
        return 0
    fi

    # Skip if settings.json exists and force is not set
    if [ -f "$settings_file" ] && [ "${MCP_FORCE_CONFIG:-false}" != "true" ]; then
        return 0
    fi

    mkdir -p "$config_dir"

    # Build the mcpServers object by merging sources with jq
    local mcp_json='{}'

    # Source 1: BRAVE_API_KEY convenience shortcut
    if [ -n "${BRAVE_API_KEY:-}" ]; then
        mcp_json=$(echo "$mcp_json" | jq --arg key "$BRAVE_API_KEY" \
            '. + {"brave-search": {"command": "npx", "args": ["-y", "@anthropic-ai/claude-code-mcp-server-brave-search"], "env": {"BRAVE_API_KEY": $key}}}')
    fi

    # Source 2: MCP_SERVERS_FILE (mounted JSON file)
    if [ -n "${MCP_SERVERS_FILE:-}" ] && [ -f "${MCP_SERVERS_FILE}" ]; then
        local file_json
        file_json=$(cat "$MCP_SERVERS_FILE")
        # Accept either {"mcpServers": {...}} or bare {...} format
        local file_servers
        file_servers=$(echo "$file_json" | jq 'if has("mcpServers") then .mcpServers else . end' 2>/dev/null) || {
            echo "[entrypoint] WARNING: Failed to parse MCP_SERVERS_FILE ($MCP_SERVERS_FILE), skipping" >&2
            file_servers='{}'
        }
        mcp_json=$(echo "$mcp_json" "$file_servers" | jq -s '.[0] * .[1]')
    fi

    # Source 3: MCP_SERVERS inline JSON
    if [ -n "${MCP_SERVERS:-}" ]; then
        local inline_servers
        # Accept either {"mcpServers": {...}} or bare {...} format
        inline_servers=$(echo "$MCP_SERVERS" | jq 'if has("mcpServers") then .mcpServers else . end' 2>/dev/null) || {
            echo "[entrypoint] WARNING: Failed to parse MCP_SERVERS env var, skipping" >&2
            inline_servers='{}'
        }
        mcp_json=$(echo "$mcp_json" "$inline_servers" | jq -s '.[0] * .[1]')
    fi

    # Write settings.json with the merged MCP config
    echo "$mcp_json" | jq '{mcpServers: .}' > "$settings_file"

    # Fix ownership for the running user
    chown "$USER_UID:$USER_GID" "$settings_file" 2>/dev/null || true

    local server_count
    server_count=$(echo "$mcp_json" | jq 'keys | length')
    echo "[entrypoint] MCP config written to $settings_file ($server_count server(s))"
}

# ── Main ──────────────────────────────────────────────────────────────

# If running as root (UID 0), stay as root
if [ "$USER_UID" -eq 0 ]; then
    setup_ssh_user
    start_sshd
    setup_mcp_config
    setup_docker_socket
    exec "$@"
fi

# Create group if it doesn't exist
if ! getent group "$USER_GID" >/dev/null 2>&1; then
    groupadd -g "$USER_GID" claude 2>/dev/null || true
else
    EXISTING_GROUP=$(getent group "$USER_GID" | cut -d: -f1)
    if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "claude" ]; then
        GROUP_NAME="$EXISTING_GROUP"
    else
        GROUP_NAME="claude"
    fi
fi

# Default group name if not set
GROUP_NAME=${GROUP_NAME:-claude}

# Create user if it doesn't exist
if ! getent passwd "$USER_UID" >/dev/null 2>&1; then
    useradd -u "$USER_UID" -g "$GROUP_NAME" -m -d /home/claude -s /bin/bash claude 2>/dev/null || true
    USER_NAME="claude"
else
    USER_NAME=$(getent passwd "$USER_UID" | cut -d: -f1)
fi

# Ensure config directory is accessible without modifying existing credential files
if [ -d /claude ]; then
    chown "$USER_UID:$USER_GID" /claude 2>/dev/null || true
    chmod 755 /claude 2>/dev/null || true
fi

# Ensure workspace directory is accessible
if [ -d /workspace ]; then
    chmod 755 /workspace 2>/dev/null || true
fi

# Run root-level setup
setup_ssh_user
start_sshd
setup_mcp_config
setup_docker_socket

# Switch to the user and execute the command
export SHELL=/bin/bash
exec gosu "${USER_NAME}" "$@"
