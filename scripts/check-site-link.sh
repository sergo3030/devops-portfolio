#!/usr/bin/env bash
# Checks that the site is built for the API that production runs now.
#   check-site-link.sh <function-url> <env-file>
# The site reads VITE_API_URL from web/.env.production. The function URL changes whenever the
# function is destroyed and created again, and then the site would keep calling the old address
# and show "API offline". The two addresses are compared as origins (no trailing slash).
set -euo pipefail

deployed="${1:?usage: check-site-link.sh <function-url> <env-file>}"
env_file="${2:?usage: check-site-link.sh <function-url> <env-file>}"

if [ ! -f "${env_file}" ]; then
  echo "${env_file} does not exist: the site is not set up to call the API" >&2
  exit 1
fi

configured="$(sed -n 's/^VITE_API_URL=//p' "${env_file}" | tail -n 1 | tr -d '\r')"
deployed="${deployed%/}"
configured="${configured%/}"

if [ -z "${configured}" ]; then
  echo "${env_file} sets no VITE_API_URL: the site does not call the API" >&2
  exit 1
fi

if [ "${configured}" != "${deployed}" ]; then
  echo "the site is built for ${configured}, but production runs at ${deployed}." >&2
  echo "Update VITE_API_URL in web/.env.production in a pull request (docs/runbook-prod.md)." >&2
  exit 1
fi

echo "the site calls the API that production runs (${configured})"
