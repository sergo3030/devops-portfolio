#!/usr/bin/env bash
# Installs the Trivy image scanner, pinned by version and by the SHA-256 of the release archive.
# No action is used: an unpinned or tampered download fails the checksum and installs nothing.
# Dependabot does not track this version (see docs/decisions.md D39), so update both values
# together, and check the new archive against the release's trivy_<version>_checksums.txt.
#
#   install-trivy.sh            installs into $RUNNER_TEMP/trivy-bin and adds it to $GITHUB_PATH
#
# Environment: TRIVY_INSTALL_DIR (where to put it) and TRIVY_DOWNLOAD_BASE (a different download
# location, which the tests use). The checksum always applies.
set -euo pipefail

version="0.75.0"
sha256="c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f"
archive="trivy_${version}_Linux-64bit.tar.gz"
base="${TRIVY_DOWNLOAD_BASE:-https://github.com/aquasecurity/trivy/releases/download/v${version}}"
dest="${TRIVY_INSTALL_DIR:-${RUNNER_TEMP:-/tmp}/trivy-bin}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl --fail --silent --show-error --location --retry 3 --retry-delay 10 \
  --output "${work}/${archive}" "${base}/${archive}"
echo "${sha256}  ${work}/${archive}" | sha256sum --check --strict

mkdir -p "${dest}"
tar -xzf "${work}/${archive}" -C "${dest}" trivy
chmod +x "${dest}/trivy"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${dest}" >>"${GITHUB_PATH}"
fi
"${dest}/trivy" --version | head -n 1
