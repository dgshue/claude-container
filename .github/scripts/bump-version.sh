#!/usr/bin/env bash
# bump-version.sh — Increment the patch version based on the latest git tag.
# Outputs the new version string. Creates and pushes the tag.
# Usage: bump-version.sh [--push]
set -euo pipefail

PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

# Get the latest semver tag
LATEST_TAG=$(git tag -l --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

if [[ -z "$LATEST_TAG" ]]; then
  echo "No existing semver tags found. Starting at 2.0.0"
  NEW_VERSION="2.0.0"
else
  IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST_TAG"
  PATCH=$((PATCH + 1))
  NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
fi

echo "Version: ${LATEST_TAG:-none} → ${NEW_VERSION}"
echo "version=${NEW_VERSION}" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "previous=${LATEST_TAG:-none}" >> "${GITHUB_OUTPUT:-/dev/null}"

echo "$NEW_VERSION"
