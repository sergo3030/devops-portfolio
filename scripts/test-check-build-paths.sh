#!/usr/bin/env bash
# Tests scripts/check-build-paths.sh on the real files and on edited copies. Run from the
# repository root.
set -euo pipefail

script="$(pwd)/scripts/check-build-paths.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

expect() { # <name> <expected-exit> <output must contain, or empty> <args...>
  local name="$1" want="$2" text="$3" got=0
  shift 3
  bash "${script}" "$@" >"${work}/out" 2>&1 || got=$?
  if [ "${got}" != "${want}" ]; then
    fail "${name} (exit ${got}, wanted ${want}): $(cat "${work}/out")"
  elif [ -n "${text}" ] && ! grep -qF -- "${text}" "${work}/out"; then
    fail "${name}: output does not say '${text}': $(cat "${work}/out")"
  else
    pass "${name}"
  fi
}

cp .github/workflows/build.yml "${work}/build.yml"
cp .dockerignore "${work}/dockerignore"
cp app/Dockerfile "${work}/Dockerfile"

expect "the real files agree" 0 "the build paths match the image" \
  .github/workflows/build.yml .dockerignore app/Dockerfile

# A path removed from the workflow: the image could change without a build.
grep -v '"app/uv.lock"' "${work}/build.yml" >"${work}/no-lock.yml"
expect "a missing uv.lock is caught" 1 "app/uv.lock" "${work}/no-lock.yml" "${work}/dockerignore" "${work}/Dockerfile"

grep -v '"app/portfolio_api/\*\*"' "${work}/build.yml" >"${work}/no-package.yml"
expect "a missing package folder is caught" 1 "app/portfolio_api/**" "${work}/no-package.yml" "${work}/dockerignore" "${work}/Dockerfile"

grep -v '"app/Dockerfile"' "${work}/build.yml" >"${work}/no-dockerfile.yml"
expect "a missing Dockerfile is caught" 1 "Dockerfile" "${work}/no-dockerfile.yml" "${work}/dockerignore" "${work}/Dockerfile"

# A new file allowed into the build context and copied by the Dockerfile.
{ cat "${work}/dockerignore"; printf '!app/new_settings.toml\n'; } >"${work}/di-new"
expect "a new allowed file that no path covers is caught" 1 "app/new_settings.toml" \
  "${work}/build.yml" "${work}/di-new" "${work}/Dockerfile"

{ cat "${work}/Dockerfile"; printf 'COPY extra/data.json ./data.json\n'; } >"${work}/df-new"
expect "a new COPY source that no path covers is caught" 1 "extra/data.json" \
  "${work}/build.yml" "${work}/dockerignore" "${work}/df-new"

# Too broad: a pattern that matches tests makes every test change ask for an approval.
sed 's#"app/portfolio_api/\*\*"#"app/**"#' "${work}/build.yml" >"${work}/broad.yml"
expect "an app/** pattern (which matches the tests) is caught" 1 "app/tests/test_x.py starts a build" \
  "${work}/broad.yml" "${work}/dockerignore" "${work}/Dockerfile"

{ cat "${work}/build.yml"; } | sed 's#      - "docker-compose.yml"#      - "docker-compose.yml"\n      - "docs/**"#' >"${work}/docs.yml"
expect "a docs/** pattern is caught" 1 "docs/runbook-prod.md starts a build" \
  "${work}/docs.yml" "${work}/dockerignore" "${work}/Dockerfile"

# COPY --from lines read from other stages, not from the context: they are not required.
expect "COPY --from lines are not treated as context files" 0 "" \
  .github/workflows/build.yml .dockerignore app/Dockerfile

[ "${failures}" -eq 0 ] || { echo "${failures} failure(s)" >&2; exit 1; }
echo "all tests passed"
