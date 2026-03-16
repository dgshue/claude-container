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
setup_mcp_config() {
    local config_dir="${CLAUDE_CONFIG_DIR:-/claude}"
    local settings_file="${config_dir}/settings.json"
    local template="/opt/claude-mcp-template.json"

    # Only create if BRAVE_API_KEY is set and settings.json doesn't already exist
    if [ -n "${BRAVE_API_KEY:-}" ] && [ ! -f "$settings_file" ]; then
        mkdir -p "$config_dir"
        sed "s/__BRAVE_API_KEY__/${BRAVE_API_KEY}/g" "$template" > "$settings_file"
        # Fix ownership for the running user
        chown "$USER_UID:$USER_GID" "$settings_file" 2>/dev/null || true
    fi
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
