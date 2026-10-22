#!/usr/bin/env bash
# Scans a local image with Trivy and fails on a problem that can be fixed.
#
#   scan-image.sh <image>
#
# The policy:
#   - HIGH and CRITICAL vulnerabilities fail the scan, but only those that have a fixed version
#     (--ignore-unfixed): there is nothing to do about the others except wait.
#   - A secret in the image fails the scan.
#   - Exceptions live in .trivyignore.yaml, and each needs a reason and an expiry date.
# The vulnerability database comes from public ECR first and GHCR second, because either one
# can answer "429 Too Many Requests" to the shared GitHub runners. The download is retried.
set -euo pipefail

image="${1:?usage: scan-image.sh <image>}"
ignorefile="${TRIVY_IGNOREFILE:-.trivyignore.yaml}"
db_repositories="public.ecr.aws/aquasecurity/trivy-db:2,ghcr.io/aquasecurity/trivy-db:2"

command -v trivy >/dev/null || { echo "trivy is not installed (run scripts/install-trivy.sh)" >&2; exit 1; }

scan() {
  trivy image \
    --scanners vuln,secret \
    --severity HIGH,CRITICAL \
    --ignore-unfixed \
    --exit-code 1 \
    --ignorefile "${ignorefile}" \
    --skip-db-update \
    --skip-version-check \
    --no-progress \
    "${image}"
}

# Trivy exits 1 both for findings and for a failed database download, and only the download is
# worth repeating. Download the database on its own first (retried), then scan once.
bash "$(dirname "$0")/retry.sh" 4 30 -- \
  trivy image --download-db-only --db-repository "${db_repositories}" --no-progress

status=0
scan || status=$?
if [ "${status}" -ne 0 ]; then
  echo "scan-image.sh: ${image} has HIGH or CRITICAL findings that can be fixed, or a secret (see above)" >&2
  exit "${status}"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "- Trivy: no fixable HIGH or CRITICAL vulnerabilities and no secrets in \`${image}\`" >>"${GITHUB_STEP_SUMMARY}"
fi
echo "scan-image.sh: ${image} passed"
