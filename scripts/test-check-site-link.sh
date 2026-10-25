#!/usr/bin/env bash
# Tests scripts/check-site-link.sh. Run from the repository root.
set -euo pipefail

script="$(pwd)/scripts/check-site-link.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

url="https://abc123.lambda-url.us-east-1.on.aws"

expect() { # <name> <expected-exit> <function-url> <env-file>
  local name="$1" want="$2" got=0
  bash "${script}" "$3" "$4" >"${work}/out" 2>&1 || got=$?
  if [ "${got}" = "${want}" ]; then pass "${name}"; else fail "${name} (exit ${got}, wanted ${want}): $(cat "${work}/out")"; fi
}

printf '# a comment\nVITE_API_URL=%s\n' "${url}" >"${work}/same"
expect "the same address passes" 0 "${url}/" "${work}/same"
expect "a trailing slash on either side does not matter" 0 "${url}" "${work}/same"

printf 'VITE_API_URL=%s/\n' "${url}" >"${work}/slash"
expect "a trailing slash in the file does not matter" 0 "${url}/" "${work}/slash"

printf 'VITE_API_URL=%s\r\n' "${url}" >"${work}/crlf"
expect "Windows line endings do not matter" 0 "${url}/" "${work}/crlf"

printf 'VITE_API_URL=https://zzz999.lambda-url.us-east-1.on.aws\n' >"${work}/old"
expect "a recreated function (a different address) fails" 1 "${url}/" "${work}/old"
grep -q "Update VITE_API_URL" "${work}/out" && pass "the failure says what to do" || fail "the failure does not say what to do"

printf '# VITE_API_URL=%s\n' "${url}" >"${work}/commented"
expect "a commented-out address fails" 1 "${url}/" "${work}/commented"

printf 'SOMETHING=else\n' >"${work}/unset"
expect "no address in the file fails" 1 "${url}/" "${work}/unset"
expect "a missing file fails" 1 "${url}/" "${work}/missing"

[ "${failures}" -eq 0 ] || { echo "${failures} failure(s)" >&2; exit 1; }
echo "all tests passed"
