# DevOps Workstation based on Debian Bookworm with Node.js 22
FROM node:22-bookworm

# ── 1. System packages ───────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    git bash openssh-server \
    python3 python3-pip python3-venv \
    curl wget jq httpie \
    vim nano tmux tree \
    sudo rsync \
    iputils-ping dnsutils netcat-openbsd iproute2 \
    apt-transport-https ca-certificates gnupg lsb-release \
    make build-essential \
    ffmpeg unzip \
    chromium \
    xauth x11-utils libgl1 \
  && rm -rf /var/lib/apt/lists/*

# ── 1b. Google Chrome ────────────────────────────────────────────────
RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb \
  && apt-get update && apt-get install -y --no-install-recommends /tmp/chrome.deb \
  && rm /tmp/chrome.deb && rm -rf /var/lib/apt/lists/*

# ── 2. gosu (replaces Alpine su-exec for privilege dropping) ─────────
ARG GOSU_VERSION=1.17
RUN arch="$(dpkg --print-architecture)" \
  && curl -fsSL "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${arch}" \
       -o /usr/local/bin/gosu \
  && chmod +x /usr/local/bin/gosu \
  && gosu --version

# ── 3. PowerShell from Microsoft Debian 12 repo ─────────────────────
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
  && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/microsoft-debian-bookworm-prod bookworm main" \
       > /etc/apt/sources.list.d/microsoft.list \
  && apt-get update && apt-get install -y --no-install-recommends powershell \
  && rm -rf /var/lib/apt/lists/*

# ── 4. GitHub CLI (gh) ──────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# ── 5. Azure CLI via pip + all extensions ────────────────────────────
RUN pip3 install --break-system-packages azure-cli \
  && az extension list-available --query "[].name" -o tsv | xargs -I {} az extension add --name {} --yes 2>/dev/null || true

# ── 6. Docker CLI + Compose plugin ──────────────────────────────────
RUN curl -fsSL https://download.docker.com/linux/debian/gpg \
       | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
       https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends \
       docker-ce-cli docker-compose-plugin \
  && rm -rf /var/lib/apt/lists/*

# ── 7. Infrastructure tools (Terraform, kubectl, Helm) ──────────────
ARG TERRAFORM_VERSION=1.15.0-beta2
ARG KUBECTL_VERSION=1.35.3
ARG HELM_VERSION=3.16.4

RUN arch="$(dpkg --print-architecture)" \
  # ── Terraform ──
  && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip" \
       -o /tmp/terraform.zip \
  && unzip /tmp/terraform.zip -d /usr/local/bin/ \
  && rm /tmp/terraform.zip \
  && terraform --version \
  # ── kubectl ──
  && curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${arch}/kubectl" \
       -o /usr/local/bin/kubectl \
  && chmod +x /usr/local/bin/kubectl \
  && kubectl version --client \
  # ── Helm ──
  && curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${arch}.tar.gz" \
       | tar xz -C /tmp \
  && mv /tmp/linux-${arch}/helm /usr/local/bin/helm \
  && rm -rf /tmp/linux-${arch} \
  && helm version

# ── 8. Python pip packages ───────────────────────────────────────────
RUN pip3 install --break-system-packages \
    # HTTP / API clients
    requests httpx aiohttp \
    # Azure DevOps & management
    azure-devops msrest pywinrm \
    azure-identity azure-mgmt-resource azure-mgmt-costmanagement \
    azure-keyvault-secrets azure-data-tables \
    # Auth & security
    msal python-jose cryptography \
    # Web frameworks
    fastapi "uvicorn[standard]" \
    flask flask-cors flask-socketio \
    # Networking & discovery
    dnspython zeroconf \
    # Real-time & async
    python-socketio eventlet aiosqlite \
    # Scheduling
    schedule \
    # Browser automation
    playwright \
    # Config & utilities
    pyyaml python-dotenv \
    rich tabulate

# ── 9. Playwright + Chromium ──────────────────────────────────────────
RUN npm install -g --force playwright \
  && npx playwright install --with-deps chromium

# ── 10. Claude Code ──────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code@~2.1.96

# ── 10b. GSD Pi (v2) — coding agent harness ─────────────────────────
RUN npm install -g gsd-pi@~2.66.1

# ── 10c. mcporter — MCP server runtime/CLI for Pi ───────────────────
RUN npm install -g mcporter

# ── 11. DevOps linting & security tools ──────────────────────────────
ARG HADOLINT_VERSION=2.12.0
ARG TRIVY_VERSION=0.69.3
ARG GITLEAKS_VERSION=8.22.1

RUN arch="$(dpkg --print-architecture)" \
  # ── hadolint (Dockerfile linter) ──
  && case "$arch" in \
       amd64) hl_arch="x86_64" ;; \
       arm64) hl_arch="arm64" ;; \
       *) hl_arch="$arch" ;; \
     esac \
  && curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${hl_arch}" \
       -o /usr/local/bin/hadolint \
  && chmod +x /usr/local/bin/hadolint \
  # ── trivy (container security scanner) ──
  && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
       | tar xz -C /usr/local/bin trivy \
  && trivy --version \
  # ── gitleaks (secret detection) ──
  && case "$arch" in \
       amd64) gl_arch="x64" ;; \
       arm64) gl_arch="arm64" ;; \
       *) gl_arch="$arch" ;; \
     esac \
  && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gl_arch}.tar.gz" \
       | tar xz -C /usr/local/bin gitleaks \
  && gitleaks version

# ── 12. SSH server configuration ─────────────────────────────────────
RUN mkdir -p /var/run/sshd \
  && sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
  && sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
  && sed -i 's/^#*X11Forwarding.*/X11Forwarding yes/' /etc/ssh/sshd_config \
  && sed -i 's/^#*X11UseLocalhost.*/X11UseLocalhost no/' /etc/ssh/sshd_config \
  && ssh-keygen -A

# ── 13. Directories, MCP template, entrypoint, expose ───────────────
RUN mkdir -p /claude /workspace

COPY mcp-settings.json /opt/claude-mcp-template.json
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["bash", "-c", "echo 'Claude Code DevOps workstation is ready!' && sleep infinity"]
