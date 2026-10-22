#!/usr/bin/env bash
# Tests scripts/retry.sh, scripts/install-trivy.sh and scripts/scan-image.sh without a network,
# Docker or the real Trivy: a retry that succeeds, a retry that gives up, a tampered download
# that must be refused, and the exact policy flags the scan passes to Trivy. Run from the
# repository root.
set -euo pipefail

root="$(pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/bin"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

# ---------------------------------------------------------------- retry.sh

# A command that fails until it has been called N times: FLAKY_SUCCEED_ON picks the call.
cat >"${work}/bin/flaky" <<'EOF'
#!/usr/bin/env bash
count_file="${FLAKY_COUNT_FILE}"
count=$(( $(cat "${count_file}" 2>/dev/null || echo 0) + 1 ))
echo "${count}" >"${count_file}"
[ "${count}" -ge "${FLAKY_SUCCEED_ON}" ]
EOF
chmod +x "${work}/bin/flaky"

flaky() { # <succeed-on-call> <attempts>
  rm -f "${work}/count"
  status=0
  FLAKY_COUNT_FILE="${work}/count" FLAKY_SUCCEED_ON="$1" \
    bash "${root}/scripts/retry.sh" "$2" 0 -- "${work}/bin/flaky" 2>"${work}/err" || status=$?
  calls="$(cat "${work}/count")"
}

flaky 1 4
if [ "${status}" -eq 0 ] && [ "${calls}" -eq 1 ]; then pass "retry runs a command that works once"; else fail "a working command must run exactly once"; fi

flaky 3 4
if [ "${status}" -eq 0 ] && [ "${calls}" -eq 3 ]; then pass "retry succeeds on the third attempt and stops"; else fail "retry should stop at the first success (calls=${calls})"; fi

flaky 99 3
if [ "${status}" -ne 0 ] && [ "${calls}" -eq 3 ]; then pass "retry gives up after the last attempt and keeps failing the job"; else fail "retry must fail after 3 attempts (status=${status}, calls=${calls})"; fi

status=0
bash "${root}/scripts/retry.sh" 2 0 -- bash -c 'exit 7' 2>/dev/null || status=$?
if [ "${status}" -eq 7 ]; then pass "retry returns the command's own exit code"; else fail "exit code should be 7, got ${status}"; fi

status=0
bash "${root}/scripts/retry.sh" 0 0 -- true 2>/dev/null || status=$?
if [ "${status}" -ne 0 ]; then pass "zero attempts is rejected"; else fail "attempts must be at least 1"; fi

status=0
bash "${root}/scripts/retry.sh" 3 0 true 2>/dev/null || status=$?
if [ "${status}" -ne 0 ]; then pass "a call without -- is rejected"; else fail "the -- separator is required"; fi

# ---------------------------------------------------------------- install-trivy.sh

# A download that is not the pinned archive must fail the checksum and install nothing.
mkdir "${work}/fake-release" "${work}/fake-tool"
printf '#!/bin/sh\necho Version: evil\n' >"${work}/fake-tool/trivy"
tar -czf "${work}/fake-release/trivy_0.75.0_Linux-64bit.tar.gz" -C "${work}/fake-tool" trivy
status=0
TRIVY_DOWNLOAD_BASE="file://${work}/fake-release" TRIVY_INSTALL_DIR="${work}/installed" \
  bash "${root}/scripts/install-trivy.sh" >"${work}/out" 2>&1 || status=$?
if [ "${status}" -ne 0 ] && [ ! -e "${work}/installed/trivy" ]; then
  pass "a tampered Trivy archive fails the checksum and nothing is installed"
else fail "a download that does not match the pinned checksum must be refused"; fi

if grep -Eq '^sha256="[0-9a-f]{64}"$' "${root}/scripts/install-trivy.sh" && grep -q '^version="[0-9.]*"$' "${root}/scripts/install-trivy.sh"; then
  pass "the version and a 64-hex checksum are pinned in the script"
else fail "install-trivy.sh must pin a version and a SHA-256"; fi

# ---------------------------------------------------------------- scan-image.sh

# A fake trivy that records its arguments and succeeds or fails on demand.
cat >"${work}/bin/trivy" <<'EOF'
#!/usr/bin/env bash
echo "trivy $*" >>"${FAKE_LOG}"
case "$*" in
  *--download-db-only*) exit "${FAKE_DB_EXIT:-0}" ;;
  *) exit "${FAKE_SCAN_EXIT:-0}" ;;
esac
EOF
chmod +x "${work}/bin/trivy"

scan() { # <db-exit> <scan-exit>
  : >"${work}/log"
  status=0
  PATH="${work}/bin:${PATH}" FAKE_LOG="${work}/log" FAKE_DB_EXIT="$1" FAKE_SCAN_EXIT="$2" \
    GITHUB_STEP_SUMMARY="${work}/summary" bash "${root}/scripts/scan-image.sh" portfolio-api:ci >"${work}/out" 2>&1 || status=$?
}

: >"${work}/summary"
scan 0 0
if [ "${status}" -eq 0 ] && grep -q 'no fixable HIGH or CRITICAL' "${work}/summary"; then pass "a clean scan passes and writes the summary"; else fail "a clean scan should pass"; fi

scan_line="$(grep -v -- '--download-db-only' "${work}/log" | head -n 1)"
for flag in '--scanners vuln,secret' '--severity HIGH,CRITICAL' '--ignore-unfixed' '--exit-code 1' '--ignorefile .trivyignore.yaml' '--skip-db-update' 'portfolio-api:ci'; do
  if [[ "${scan_line}" == *"${flag}"* ]]; then pass "the scan passes ${flag}"; else fail "the scan must pass ${flag} (got: ${scan_line})"; fi
done

db_line="$(grep -- '--download-db-only' "${work}/log" | head -n 1)"
if [[ "${db_line}" == *"public.ecr.aws/aquasecurity/trivy-db:2,ghcr.io/aquasecurity/trivy-db:2"* ]]; then
  pass "the database comes from public ECR with GHCR as the fallback"
else fail "the database repositories must be public ECR then GHCR"; fi

scan 0 1
if [ "${status}" -ne 0 ] && grep -q 'can be fixed' "${work}/out"; then pass "findings fail the scan with a clear message"; else fail "a failed scan must fail"; fi

# A database that never downloads must fail the job (after the retries, which wait 30 s each
# in production; here retry.sh is replaced by a version that does not sleep).
mkdir "${work}/fast"
cp "${root}/scripts/scan-image.sh" "${work}/fast/scan-image.sh"
sed 's/sleep "\${pause}"/true/' "${root}/scripts/retry.sh" >"${work}/fast/retry.sh"
: >"${work}/log"
status=0
PATH="${work}/bin:${PATH}" FAKE_LOG="${work}/log" FAKE_DB_EXIT=1 FAKE_SCAN_EXIT=0 \
  bash "${work}/fast/scan-image.sh" portfolio-api:ci >"${work}/out" 2>&1 || status=$?
downloads="$(grep -c -- '--download-db-only' "${work}/log" || true)"
if [ "${status}" -ne 0 ] && [ "${downloads}" -eq 4 ] && ! grep -qv -- '--download-db-only' "${work}/log"; then
  pass "a database that cannot be downloaded fails after 4 attempts and no scan runs on it"
else fail "db failure: status=${status} downloads=${downloads}"; fi

if grep -Eq '^vulnerabilities: \[\]$' "${root}/.trivyignore.yaml"; then pass "the ignore file starts empty"; else fail ".trivyignore.yaml should start with no exceptions"; fi

if [ "${failures}" -ne 0 ]; then
  echo "${failures} test(s) failed" >&2
  exit 1
fi
echo "all retry and trivy script tests passed"
