#!/usr/bin/env bash
# Checks that a deployed site serves exactly the page that was built.
#   verify-site.sh <site-url> <sha256-of-the-built-index.html> [attempts]
# The page must be byte-identical to the build output, and every script and stylesheet it
# references must load. A CDN can take a minute to catch up after a deployment, so a failed
# attempt is retried (every 10 s, 9 attempts by default) before the check gives up.
set -euo pipefail

url="${1:?usage: verify-site.sh <site-url> <sha256-of-index.html> [attempts]}"
expected="${2:?usage: verify-site.sh <site-url> <sha256-of-index.html> [attempts]}"
attempts="${3:-9}"

url="${url%/}/"
origin="$(printf '%s' "${url}" | sed -E 's#^(https?://[^/]+).*#\1#')"
page="$(mktemp)"
trap 'rm -f "${page}"' EXIT

check() {
  curl --fail --silent --show-error --location --max-time 20 \
    --header 'Cache-Control: no-cache' --output "${page}" "${url}" || return 1

  actual="$(sha256sum "${page}" | cut -d' ' -f1)"
  if [ "${actual}" != "${expected}" ]; then
    echo "the served page differs from the build (served ${actual}, built ${expected})" >&2
    return 1
  fi

  assets="$(grep -oE '(src|href)="/[^"]+\.(js|css)"' "${page}" | sed -E 's/^(src|href)="//; s/"$//')"
  if [ -z "${assets}" ]; then
    echo "the page references no script or stylesheet" >&2
    return 1
  fi
  while IFS= read -r asset; do
    curl --fail --silent --show-error --location --max-time 20 --output /dev/null \
      "${origin}${asset}" || return 1
    echo "  ok ${asset}"
  done <<<"${assets}"
}

for attempt in $(seq 1 "${attempts}"); do
  if check; then
    echo "site verified: ${url}"
    exit 0
  fi
  echo "attempt ${attempt}/${attempts} failed" >&2
  [ "${attempt}" -lt "${attempts}" ] && sleep 10
done
echo "site did not verify: ${url}" >&2
exit 1
