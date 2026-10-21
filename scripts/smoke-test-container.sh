#!/usr/bin/env bash
# Smoke test of the running API container. Run it from the repository root after
# `docker compose up --build --wait`. It needs curl, jq and docker, so it runs in CI.
#
#   GIT_SHA=<commit> scripts/smoke-test-container.sh [base-url]
#
# It fails loudly: the first check that does not hold stops the script with a message.
set -euo pipefail

base_url="${1:-http://127.0.0.1:8080}"
expected_sha="${GIT_SHA:-}"
expected_version="${APP_VERSION:-0.0.0-dev}"
image="portfolio-api:ci"

fail() { echo "SMOKE TEST FAILED: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

# ---------------------------------------------------------------- /health
health="$(curl -fsS "${base_url}/health")" || fail "GET /health did not return 200"
echo "${health}" | jq -e '.status == "ok"' >/dev/null || fail "/health status is not ok: ${health}"
echo "${health}" | jq -e --arg v "${expected_version}" '.version == $v' >/dev/null \
  || fail "/health version is not ${expected_version}: ${health}"
if [ -n "${expected_sha}" ]; then
  echo "${health}" | jq -e --arg s "${expected_sha}" '.git_sha == $s' >/dev/null \
    || fail "/health git_sha does not match the built commit: ${health}"
fi
ok "/health reports status ok, version ${expected_version} and the built commit"

# ---------------------------------------------------------------- /content
headers="$(curl -fsS -o /tmp/content.json -D - "${base_url}/content")" || fail "GET /content did not return 200"
echo "${headers}" | grep -qi '^cache-control: public, max-age=300' || fail "/content has no Cache-Control header"
jq -e '(.profile | type == "object") and (.links | type == "array") and (.skills | type == "array")
       and (.experience | type == "array") and (.languages | type == "array")' /tmp/content.json >/dev/null \
  || fail "/content does not have the expected shape"
jq -e '(.case_studies | type == "array")' /tmp/content.json >/dev/null || fail "/content has no case_studies array"
# Leak guard: approval state must never reach a response.
if jq -e '[.. | objects | keys[]] | any(. == "approved" or . == "employer_approval")' /tmp/content.json >/dev/null; then
  fail "/content contains approval state"
fi
ok "/content has the expected shape, a cache header and no approval state"

# ---------------------------------------------------------------- docs routes are off
for path in /docs /redoc /openapi.json; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "${base_url}${path}")"
  [ "${code}" = "404" ] || fail "GET ${path} returned ${code}, expected 404"
done
ok "docs routes are off"

# ---------------------------------------------------------------- container hardening
uid="$(docker compose exec -T api id -u)"
[ "${uid}" != "0" ] || fail "the container runs as root"
ok "the container runs as uid ${uid}, not root"

if docker compose exec -T api sh -c 'touch /app/should-not-exist' 2>/dev/null; then
  fail "the root filesystem is writable"
fi
docker compose exec -T api sh -c 'touch /tmp/ok && rm /tmp/ok' || fail "/tmp is not writable"
ok "the root filesystem is read-only and /tmp is writable, as on Lambda"

# ---------------------------------------------------------------- image metadata
label() { docker image inspect "${image}" --format "{{ index .Config.Labels \"$1\" }}"; }
[ "$(label org.opencontainers.image.version)" = "${expected_version}" ] || fail "image version label is wrong"
if [ -n "${expected_sha}" ]; then
  [ "$(label org.opencontainers.image.revision)" = "${expected_sha}" ] || fail "image revision label is wrong"
fi
[ "$(label org.opencontainers.image.source)" != "" ] || fail "image source label is missing"
ok "the OCI labels carry the version and the commit"

echo "all smoke checks passed"
