#!/usr/bin/env bash
# Fails when a tool that Dependabot cannot update is pinned to two different versions, or is not
# pinned at all. A bump that stops half way (one workflow on the new version, another on the old)
# would otherwise go unnoticed.
#
#   check-tool-pins.sh [root]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${1:-.}"
pins="$(bash "${here}/tool-pins.sh" "${root}")"

status=0
for tool in uv tofu gitleaks hadolint trivy; do
  versions="$(awk -v t="${tool}" '$1 == t {print $2}' <<<"${pins}" | sort -u)"
  if [ -z "${versions}" ]; then
    echo "${tool} is not pinned anywhere (or its pin moved: update scripts/tool-pins.sh)" >&2
    status=1
  elif [ "$(wc -l <<<"${versions}")" -ne 1 ]; then
    echo "${tool} is pinned to more than one version: $(tr '\n' ' ' <<<"${versions}")" >&2
    status=1
  fi
done

[ "${status}" -eq 0 ] && echo "every tool has exactly one pinned version: $(sort -u <<<"${pins}" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
exit "${status}"
