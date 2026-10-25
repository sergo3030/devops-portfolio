#!/usr/bin/env bash
# Compares the tools that Dependabot cannot update (see tool-pins.sh) with their latest release,
# and fails when a pinned version is behind a release that is at least MAX_AGE_DAYS old (14 by
# default). A release younger than that is shown but does not fail: new releases wait, like the
# 7-day cooldown of Dependabot, so a broken release is not adopted on day one.
#
#   tool-versions.sh [root]
#
# Environment: GH_TOKEN (read access is enough) for the GitHub API, MAX_AGE_DAYS,
# TOOL_VERSIONS_LATEST=<file> to read "<tool> <latest version> <published ISO date>" lines
# instead of calling GitHub, and TOOL_VERSIONS_NOW=<epoch seconds> to fix the current time (tests).
# The result is also written to $GITHUB_STEP_SUMMARY when it is set.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${1:-.}"
max_age="${MAX_AGE_DAYS:-14}"
now="${TOOL_VERSIONS_NOW:-$(date +%s)}"

declare -A repository=(
  [uv]="astral-sh/uv"
  [tofu]="opentofu/opentofu"
  [gitleaks]="gitleaks/gitleaks"
  [hadolint]="hadolint/hadolint"
  [trivy]="aquasecurity/trivy"
)

latest_of() { # <tool>: prints "<version> <published date>"
  local tool="$1"
  if [ -n "${TOOL_VERSIONS_LATEST:-}" ]; then
    awk -v t="${tool}" '$1 == t {print $2, $3}' "${TOOL_VERSIONS_LATEST}"
    return
  fi
  gh api "repos/${repository[${tool}]}/releases/latest" --jq '"\(.tag_name | ltrimstr("v")) \(.published_at)"'
}

pins="$(bash "${here}/tool-pins.sh" "${root}" | sort -u)"
status=0
lines=()
for tool in uv tofu gitleaks hadolint trivy; do
  pinned="$(awk -v t="${tool}" '$1 == t {print $2}' <<<"${pins}" | tail -n 1)"
  if [ -z "${pinned}" ]; then
    lines+=("${tool}: not pinned anywhere")
    status=1
    continue
  fi
  read -r latest published <<<"$(latest_of "${tool}")"
  if [ -z "${latest:-}" ]; then
    lines+=("${tool}: ${pinned} pinned, latest release unknown (API call failed)")
    status=1
    continue
  fi
  if [ "${pinned}" = "${latest}" ]; then
    lines+=("${tool}: ${pinned} is the latest release")
    continue
  fi
  age_days=$(((now - $(date -d "${published}" +%s)) / 86400))
  if [ "${age_days}" -ge "${max_age}" ]; then
    lines+=("${tool}: ${pinned} pinned, ${latest} released ${age_days} days ago: UPDATE (see docs/stability.md)")
    status=1
  else
    lines+=("${tool}: ${pinned} pinned, ${latest} released ${age_days} days ago: waiting (under ${max_age} days)")
  fi
done

printf '%s\n' "${lines[@]}"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Tool versions"
    printf -- '- %s\n' "${lines[@]}"
  } >>"${GITHUB_STEP_SUMMARY}"
fi
exit "${status}"
