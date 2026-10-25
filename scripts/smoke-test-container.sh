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

# ---------------------------------------------------------------- hardening (task 16)
site_origin="https://sergo3030.github.io"

# Every kind of answer carries the security headers, and none of them announces the server.
for path in /health /content /nope; do
  answer="$(curl -s -D - -o /dev/null "${base_url}${path}")"
  echo "${answer}" | grep -qi '^x-content-type-options: nosniff' || fail "${path} has no nosniff header"
  echo "${answer}" | grep -qi "^content-security-policy: default-src 'none'; frame-ancestors 'none'" \
    || fail "${path} has no Content-Security-Policy"
  echo "${answer}" | grep -qi '^referrer-policy: no-referrer' || fail "${path} has no Referrer-Policy"
  echo "${answer}" | grep -qi '^strict-transport-security: ' || fail "${path} has no Strict-Transport-Security"
  if echo "${answer}" | grep -qi '^server:'; then fail "${path} announces a server header"; fi
done
curl -s -D - -o /dev/null "${base_url}/health" | grep -qi '^cache-control: no-store' || fail "/health may be cached"
ok "every answer carries the security headers, none announces the server, /health is not cacheable"

# CORS: only the site's origin may read the API in a browser.
allowed="$(curl -s -D - -o /dev/null -H "Origin: ${site_origin}" "${base_url}/content" | tr -d '\r')"
echo "${allowed}" | grep -qix "access-control-allow-origin: ${site_origin}" || fail "the site origin is not allowed by CORS"
if echo "${allowed}" | grep -qi '^access-control-allow-credentials'; then fail "CORS allows credentials"; fi
other="$(curl -s -D - -o /dev/null -H "Origin: https://evil.example" "${base_url}/content")"
if echo "${other}" | grep -qi '^access-control-allow-origin'; then fail "another origin is allowed by CORS"; fi
preflight="$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS -H "Origin: ${site_origin}" \
  -H 'Access-Control-Request-Method: GET' "${base_url}/content")"
[ "${preflight}" = "200" ] || fail "the CORS preflight for GET answered ${preflight}"
bad_preflight="$(curl -s -o /dev/null -w '%{http_code}' -X OPTIONS -H "Origin: ${site_origin}" \
  -H 'Access-Control-Request-Method: POST' "${base_url}/content")"
[ "${bad_preflight}" = "400" ] || fail "the CORS preflight for POST answered ${bad_preflight}"
ok "CORS allows only the site's origin, GET, and no credentials"

# The API only reads: other methods and request bodies are refused.
post="$(curl -s -o /dev/null -w '%{http_code}' -X POST "${base_url}/content")"
[ "${post}" = "405" ] || fail "POST answered ${post}, expected 405"
body="$(curl -s -o /dev/null -w '%{http_code}' -X GET --data 'x' "${base_url}/health")"
[ "${body}" = "413" ] || fail "a GET with a body answered ${body}, expected 413"
ok "other methods are refused (405) and a request body is refused (413)"

big_header="$(head -c 20000 /dev/zero | tr '\0' 'a')"
too_big="$(curl -s -o /dev/null -w '%{http_code}' -H "X-Big: ${big_header}" "${base_url}/health")"
[ "${too_big}" = "431" ] || fail "20 KB of headers answered ${too_big}, expected 431"
long_url="$(curl -s -o /dev/null -w '%{http_code}' "${base_url}/health?x=$(head -c 3000 /dev/zero | tr '\0' 'a')")"
[ "${long_url}" = "414" ] || fail "a 3 KB URL answered ${long_url}, expected 414"
ok "oversized headers (431) and URLs (414) are refused"

# No secrets in the image: no secret-looking variable, and none of the usual secret files.
env_names="$(docker image inspect "${image}" --format '{{range .Config.Env}}{{println .}}{{end}}' | cut -d= -f1)"
# GPG_KEY is set by the official python base image: the public ID of the key that signs Python
# releases, not a secret. It is the one name allowed to look like one.
if echo "${env_names}" | grep -vx 'GPG_KEY' | grep -Ei 'KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL'; then
  fail "the image sets a secret-looking environment variable"
fi
# `find` exits non-zero when it cannot read a directory (the app user cannot read all of /), so its
# exit status is ignored: only what it prints counts.
leftovers="$(docker compose exec -T api sh -c \
  "find / -xdev \\( -name '.env*' -o -name '.git' -o -name 'id_rsa*' -o -name '*.tfstate' -o -name '*.tfvars' \\) 2>/dev/null || true")"
[ -z "${leftovers}" ] || fail "the image contains secret-looking files: ${leftovers}"
app_files="$(docker compose exec -T api ls -A /app | tr -d '\r' | sort | tr '\n' ' ')"
[ "${app_files}" = "content.public.json portfolio_api " ] || fail "/app holds unexpected files: ${app_files}"
ok "the image has no secret-looking variable or file, and /app holds only the app and its content"

echo "all smoke checks passed"
