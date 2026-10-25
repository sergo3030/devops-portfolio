#!/usr/bin/env bash
# Tests tool-pins.sh, check-tool-pins.sh and tool-versions.sh on small made-up repositories and on
# the real one. No network: the latest releases come from a fixture file. Run from the repository
# root.
set -euo pipefail

repo="$(pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

# A fake repository whose pins can be edited per test.
fixture() { # <dir>
  local dir="$1"
  mkdir -p "${dir}/.github/workflows" "${dir}/scripts"
  cat >"${dir}/.github/workflows/ci.yml" <<'YAML'
jobs:
  one:
    steps:
      - name: Set up uv
        uses: astral-sh/setup-uv@abc # v1
        with:
          version: "0.13.1"
          enable-cache: false
      - name: Install gitleaks
        env:
          GITLEAKS_VERSION: "8.30.1"
      - name: Install hadolint
        env:
          HADOLINT_VERSION: "2.15.1"
YAML
  cat >"${dir}/.github/workflows/deploy.yml" <<'YAML'
jobs:
  deploy:
    steps:
      - uses: opentofu/setup-opentofu@abc # v1
        with:
          tofu_version: "1.13.1"
      - name: Set up uv
        uses: astral-sh/setup-uv@abc # v1
        with:
          version: "0.13.1"
YAML
  printf '#!/usr/bin/env bash\nversion="0.75.0"\nsha256="abc"\n' >"${dir}/scripts/install-trivy.sh"
}

expect() { # <name> <expected exit> <text that must be in the output> <command...>
  local name="$1" want="$2" text="$3" got=0
  shift 3
  "$@" >"${work}/out" 2>&1 || got=$?
  if [ "${got}" != "${want}" ]; then
    fail "${name} (exit ${got}, wanted ${want}): $(cat "${work}/out")"
  elif [ -n "${text}" ] && ! grep -qF -- "${text}" "${work}/out"; then
    fail "${name}: output does not say '${text}': $(cat "${work}/out")"
  else
    pass "${name}"
  fi
}

pins="${repo}/scripts/tool-pins.sh"
check="${repo}/scripts/check-tool-pins.sh"
versions="${repo}/scripts/tool-versions.sh"

fixture "${work}/ok"
out="$(bash "${pins}" "${work}/ok" | sort | tr '\n' ',')"
[ "${out}" = "gitleaks 8.30.1,hadolint 2.15.1,tofu 1.13.1,trivy 0.75.0,uv 0.13.1,uv 0.13.1," ] \
  && pass "every pin is found, uv in both workflows" || fail "pins found: ${out}"

expect "consistent pins pass" 0 "every tool has exactly one pinned version" bash "${check}" "${work}/ok"

fixture "${work}/uv-split"
sed -i '0,/0.13.1/s//0.13.2/' "${work}/uv-split/.github/workflows/deploy.yml"
expect "a half-done uv bump is caught" 1 "uv is pinned to more than one version" bash "${check}" "${work}/uv-split"

fixture "${work}/no-trivy"
rm "${work}/no-trivy/scripts/install-trivy.sh"
expect "a missing pin is caught" 1 "trivy is not pinned anywhere" bash "${check}" "${work}/no-trivy"

fixture "${work}/moved"
sed -i 's/GITLEAKS_VERSION/GITLEAKS_RELEASE/' "${work}/moved/.github/workflows/ci.yml"
expect "a pin that moved (renamed variable) is noticed, not silently ignored" 1 "gitleaks is not pinned anywhere" bash "${check}" "${work}/moved"

expect "the real repository is consistent" 0 "every tool has exactly one pinned version" bash "${check}" "${repo}"

# ------------------------------------------------------------------ tool-versions.sh
now="$(date -d 2026-10-25T12:00:00Z +%s)"
latest="${work}/latest"
cat >"${latest}" <<'EOF'
uv 0.13.1 2026-10-01T00:00:00Z
tofu 1.13.1 2026-10-01T00:00:00Z
gitleaks 8.30.1 2026-09-01T00:00:00Z
hadolint 2.15.1 2026-09-01T00:00:00Z
trivy 0.75.0 2026-10-01T00:00:00Z
EOF
run_versions() { TOOL_VERSIONS_LATEST="${latest}" TOOL_VERSIONS_NOW="${now}" bash "${versions}" "$1"; }

expect "everything on its latest release passes" 0 "gitleaks: 8.30.1 is the latest release" run_versions "${work}/ok"

sed -i 's/^uv .*/uv 0.13.5 2026-10-22T00:00:00Z/' "${latest}"
expect "a release younger than the cooldown only waits" 0 "uv: 0.13.1 pinned, 0.13.5 released 3 days ago: waiting" run_versions "${work}/ok"

sed -i 's/^uv .*/uv 0.13.5 2026-10-01T00:00:00Z/' "${latest}"
expect "a release older than the cooldown fails the run" 1 "UPDATE" run_versions "${work}/ok"
sed -i 's/^uv .*/uv 0.13.1 2026-10-01T00:00:00Z/' "${latest}"

sed -i '/^trivy/d' "${latest}"
expect "an unknown latest release fails instead of passing quietly" 1 "latest release unknown" run_versions "${work}/ok"
echo "trivy 0.75.0 2026-10-01T00:00:00Z" >>"${latest}"

summary="${work}/summary.md"
TOOL_VERSIONS_LATEST="${latest}" TOOL_VERSIONS_NOW="${now}" GITHUB_STEP_SUMMARY="${summary}" bash "${versions}" "${work}/ok" >/dev/null
grep -q "### Tool versions" "${summary}" && pass "the result goes to the job summary" || fail "no job summary written"

[ "${failures}" -eq 0 ] || { echo "${failures} failure(s)" >&2; exit 1; }
echo "all tests passed"
