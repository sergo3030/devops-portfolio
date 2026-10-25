#!/usr/bin/env bash
# Prints the versions of the tools that are pinned in the repository but that Dependabot cannot
# update, one "<tool> <version>" line for each place a version is written.
#
#   tool-pins.sh [root]        (the repository root, by default the current directory)
#
# Used by check-tool-pins.sh (the same tool must have one version everywhere) and by
# tool-versions.sh (is a pinned version far behind its latest release?). The tools are:
#   uv        the `version:` input of astral-sh/setup-uv, in every workflow
#   tofu      the `tofu_version:` input of opentofu/setup-opentofu
#   gitleaks  GITLEAKS_VERSION in ci.yml (also pinned by checksum)
#   hadolint  HADOLINT_VERSION in ci.yml (also pinned by checksum)
#   trivy     `version=` in scripts/install-trivy.sh (also pinned by checksum)
# The Python tools (actionlint, zizmor, checkov and others) are locked in tools/ and updated by
# Dependabot, so they are not listed here.
set -euo pipefail

root="${1:-.}"
workflows="${root}/.github/workflows"

for file in "${workflows}"/*.yml; do
  [ -f "${file}" ] || continue
  # The version input follows the `uses: astral-sh/setup-uv` line within a few lines.
  awk '
    /uses: astral-sh\/setup-uv/ { watch = 4; next }
    watch > 0 && /^[[:space:]]+version:/ {
      gsub(/[^0-9.]/, "", $2); print "uv " $2; watch = 0; next
    }
    watch > 0 { watch-- }
  ' "${file}"
  sed -n 's/^[[:space:]]*tofu_version:[[:space:]]*"\([^"]*\)".*/tofu \1/p' "${file}"
  sed -n 's/^[[:space:]]*GITLEAKS_VERSION:[[:space:]]*"\([^"]*\)".*/gitleaks \1/p' "${file}"
  sed -n 's/^[[:space:]]*HADOLINT_VERSION:[[:space:]]*"\([^"]*\)".*/hadolint \1/p' "${file}"
done

if [ -f "${root}/scripts/install-trivy.sh" ]; then
  sed -n 's/^version="\([^"]*\)".*/trivy \1/p' "${root}/scripts/install-trivy.sh"
fi
