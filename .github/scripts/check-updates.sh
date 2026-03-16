#!/usr/bin/env bash
# check-updates.sh — Resolve latest versions for all pinned packages in the Dockerfile.
# Outputs a JSON manifest of current→latest mappings and whether any changed.
# Exit 0 = updates found, exit 1 = error, exit 2 = already up-to-date.
set -euo pipefail

DOCKERFILE="${1:-claude-code/Dockerfile}"

###############################################################################
# Helpers
###############################################################################

# Latest GitHub release tag (strips leading 'v')
gh_latest() {
  local repo="$1"
  local tag
  tag=$(curl -fsSL -H "Authorization: token ${GITHUB_TOKEN:-}" \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -r '.tag_name // empty')
  echo "${tag#v}"
}

# Latest stable npm version for a package
npm_latest() {
  local pkg="$1"
  npm view "${pkg}" version 2>/dev/null
}

# Latest stable npm version matching a major prefix (e.g. 2.x)
npm_latest_major() {
  local pkg="$1" major="$2"
  npm view "${pkg}" versions --json 2>/dev/null \
    | jq -r --arg m "${major}." '[.[] | select(startswith($m)) | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | last // empty'
}

# Latest kubectl stable version
kubectl_latest() {
  curl -fsSL "https://dl.k8s.io/release/stable.txt" | sed 's/^v//'
}

# Latest Terraform version from releases API
terraform_latest() {
  curl -fsSL "https://api.releases.hashicorp.com/v1/releases/terraform?limit=1" \
    | jq -r '.[0].version // empty'
}

# Read current ARG value from Dockerfile
dockerfile_arg() {
  local name="$1"
  grep -oP "^ARG ${name}=\K.*" "$DOCKERFILE" 2>/dev/null || echo ""
}

# Read current npm pin from Dockerfile (e.g. @anthropic-ai/claude-code@~2.1.0 → 2.1.0)
dockerfile_npm_pin() {
  local pkg="$1"
  grep -oP "${pkg}@~?\K[0-9]+\.[0-9]+\.[0-9]+" "$DOCKERFILE" 2>/dev/null || echo ""
}

###############################################################################
# Gather current and latest versions
###############################################################################

declare -A CURRENT LATEST SOURCE
CHANGES=0

echo "::group::Checking GitHub Release packages"

# gosu
CURRENT[gosu]=$(dockerfile_arg GOSU_VERSION)
LATEST[gosu]=$(gh_latest "tianon/gosu")
SOURCE[gosu]="github:tianon/gosu"
echo "  gosu: ${CURRENT[gosu]} → ${LATEST[gosu]}"

# Terraform
CURRENT[terraform]=$(dockerfile_arg TERRAFORM_VERSION)
LATEST[terraform]=$(terraform_latest)
SOURCE[terraform]="hashicorp"
echo "  terraform: ${CURRENT[terraform]} → ${LATEST[terraform]}"

# kubectl
CURRENT[kubectl]=$(dockerfile_arg KUBECTL_VERSION)
LATEST[kubectl]=$(kubectl_latest)
SOURCE[kubectl]="dl.k8s.io"
echo "  kubectl: ${CURRENT[kubectl]} → ${LATEST[kubectl]}"

# Helm
CURRENT[helm]=$(dockerfile_arg HELM_VERSION)
LATEST[helm]=$(gh_latest "helm/helm")
SOURCE[helm]="github:helm/helm"
echo "  helm: ${CURRENT[helm]} → ${LATEST[helm]}"

# hadolint
CURRENT[hadolint]=$(dockerfile_arg HADOLINT_VERSION)
LATEST[hadolint]=$(gh_latest "hadolint/hadolint")
SOURCE[hadolint]="github:hadolint/hadolint"
echo "  hadolint: ${CURRENT[hadolint]} → ${LATEST[hadolint]}"

# trivy
CURRENT[trivy]=$(dockerfile_arg TRIVY_VERSION)
LATEST[trivy]=$(gh_latest "aquasecurity/trivy")
SOURCE[trivy]="github:aquasecurity/trivy"
echo "  trivy: ${CURRENT[trivy]} → ${LATEST[trivy]}"

# gitleaks
CURRENT[gitleaks]=$(dockerfile_arg GITLEAKS_VERSION)
LATEST[gitleaks]=$(gh_latest "gitleaks/gitleaks")
SOURCE[gitleaks]="github:gitleaks/gitleaks"
echo "  gitleaks: ${CURRENT[gitleaks]} → ${LATEST[gitleaks]}"

echo "::endgroup::"

echo "::group::Checking npm packages"

# Claude Code — pin to latest within the current major (2.x)
CURRENT[claude_code]=$(dockerfile_npm_pin "@anthropic-ai/claude-code")
LATEST[claude_code]=$(npm_latest "@anthropic-ai/claude-code")
SOURCE[claude_code]="npm:@anthropic-ai/claude-code"
echo "  claude-code: ${CURRENT[claude_code]} → ${LATEST[claude_code]}"

# gsd-pi — pin to latest within the current major (2.x)
CURRENT[gsd_pi]=$(dockerfile_npm_pin "gsd-pi")
LATEST[gsd_pi]=$(npm_latest "gsd-pi")
SOURCE[gsd_pi]="npm:gsd-pi"
echo "  gsd-pi: ${CURRENT[gsd_pi]} → ${LATEST[gsd_pi]}"

# mcporter (unpinned, just track)
CURRENT[mcporter]="unpinned"
LATEST[mcporter]=$(npm_latest "mcporter")
SOURCE[mcporter]="npm:mcporter"
echo "  mcporter: latest=${LATEST[mcporter]}"

# playwright (npm, unpinned — track)
CURRENT[playwright_npm]="unpinned"
LATEST[playwright_npm]=$(npm_latest "playwright")
SOURCE[playwright_npm]="npm:playwright"
echo "  playwright(npm): latest=${LATEST[playwright_npm]}"

echo "::endgroup::"

###############################################################################
# Build update manifest
###############################################################################

UPDATES_JSON="[]"
NOTES=""

for key in gosu terraform kubectl helm hadolint trivy gitleaks claude_code gsd_pi; do
  cur="${CURRENT[$key]}"
  lat="${LATEST[$key]}"
  if [[ -n "$lat" && "$cur" != "$lat" ]]; then
    CHANGES=$((CHANGES + 1))
    UPDATES_JSON=$(echo "$UPDATES_JSON" | jq --arg k "$key" --arg c "$cur" --arg l "$lat" --arg s "${SOURCE[$key]}" \
      '. + [{"package": $k, "current": $c, "latest": $l, "source": $s}]')
    NOTES="${NOTES}- **${key}**: ${cur} → ${lat}\n"
  fi
done

echo ""
echo "Updates found: ${CHANGES}"

if [[ $CHANGES -eq 0 ]]; then
  echo "All packages are up to date."
  echo "updates=false" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 2
fi

echo ""
echo "Update manifest:"
echo "$UPDATES_JSON" | jq .

# Write outputs for the workflow
{
  echo "updates=true"
  echo "count=${CHANGES}"
  echo "manifest<<EOF"
  echo "$UPDATES_JSON"
  echo "EOF"
  echo "notes<<EOF"
  echo -e "$NOTES"
  echo "EOF"
} >> "${GITHUB_OUTPUT:-/dev/null}"

exit 0
