#!/usr/bin/env bash
# apply-updates.sh — Read the update manifest and patch the Dockerfile in place.
# Usage: apply-updates.sh <manifest-json-file> [dockerfile]
set -euo pipefail

MANIFEST_FILE="$1"
DOCKERFILE="${2:-claude-code/Dockerfile}"

echo "Applying updates to ${DOCKERFILE}..."

# Read the manifest JSON from file
MANIFEST=$(cat "$MANIFEST_FILE")

# Map package key → Dockerfile ARG name or special handler
apply_arg_update() {
  local arg_name="$1" new_version="$2"
  echo "  Updating ARG ${arg_name} → ${new_version}"
  sed -i "s/^ARG ${arg_name}=.*/ARG ${arg_name}=${new_version}/" "$DOCKERFILE"
}

apply_npm_pin_update() {
  local pkg="$1" new_version="$2"
  echo "  Updating npm pin ${pkg} → ~${new_version}"
  # Match @~X.Y.Z or @X.Y.Z patterns
  sed -i "s|${pkg}@~\?[0-9]\+\.[0-9]\+\.[0-9]\+|${pkg}@~${new_version}|g" "$DOCKERFILE"
}

COUNT=$(echo "$MANIFEST" | jq length)
echo "Processing ${COUNT} updates..."
echo ""

for i in $(seq 0 $((COUNT - 1))); do
  PKG=$(echo "$MANIFEST" | jq -r ".[$i].package")
  NEW=$(echo "$MANIFEST" | jq -r ".[$i].latest")

  case "$PKG" in
    gosu)        apply_arg_update "GOSU_VERSION"      "$NEW" ;;
    terraform)   apply_arg_update "TERRAFORM_VERSION"  "$NEW" ;;
    kubectl)     apply_arg_update "KUBECTL_VERSION"    "$NEW" ;;
    helm)        apply_arg_update "HELM_VERSION"       "$NEW" ;;
    hadolint)    apply_arg_update "HADOLINT_VERSION"   "$NEW" ;;
    trivy)       apply_arg_update "TRIVY_VERSION"      "$NEW" ;;
    gitleaks)    apply_arg_update "GITLEAKS_VERSION"   "$NEW" ;;
    claude_code) apply_npm_pin_update "@anthropic-ai/claude-code" "$NEW" ;;
    gsd_pi)      apply_npm_pin_update "gsd-pi" "$NEW" ;;
    *)           echo "  ⚠ Unknown package: ${PKG}, skipping" ;;
  esac
done

echo ""
echo "Done. Updated ${COUNT} packages in ${DOCKERFILE}"
