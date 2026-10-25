#!/usr/bin/env bash
# Checks that the push paths of build.yml match what goes into the API image, in both directions.
#
#   check-build-paths.sh [build.yml] [.dockerignore] [Dockerfile]     (run from the repository root)
#
# Every merge that touches a path listed in build.yml builds an image and creates a deployment
# waiting for the owner's approval, so the list has to be exact:
#   - too short: a file that is copied into the image changes it without a build (a stale image);
#   - too long: a merge that cannot change the image (a test, a doc) asks for an approval.
# It fails when
#   - a path that .dockerignore allows into the build context, a file the Dockerfile copies from
#     the context, the Dockerfile, .dockerignore, docker-compose.yml or the two build workflows are
#     not covered by the paths, or
#   - one of a few paths that must never build (tests, docs, the web app, infrastructure) is covered.
set -euo pipefail

workflow="${1:-.github/workflows/build.yml}"
dockerignore="${2:-.dockerignore}"
dockerfile="${3:-app/Dockerfile}"

# The paths of the push trigger: the "- ..." lines under `paths:`.
patterns="$(awk '/^    paths:/{f=1; next} f && /^      - /{print; next} f{exit}' "${workflow}" |
  sed -E 's/^      - "?([^"]*)"?[[:space:]]*$/\1/')"
[ -n "${patterns}" ] || { echo "no paths found in ${workflow}" >&2; exit 1; }

covered() { # <path>: is it matched by one of the patterns? (** is read as *)
  local candidate="$1" pattern
  while IFS= read -r pattern; do
    pattern="${pattern//\*\*/*}"
    # shellcheck disable=SC2053 # the pattern is meant to be a glob
    # A folder (a COPY source without a slash) is covered when the files inside it are.
    if [[ "${candidate}" == ${pattern} || "${candidate}/x" == ${pattern} ]]; then return 0; fi
  done <<<"${patterns}"
  return 1
}

failures=0

# What must be covered.
required="$(
  sed -n 's/^!\(.*\)$/\1/p' "${dockerignore}" | sed -E 's#/$#/**#'
  # Sources of COPY lines that read from the build context (not `--from=`), all but the destination.
  awk '/^COPY / && !/--from=/ {for (i = 2; i < NF; i++) print $i}' "${dockerfile}"
  printf '%s\n' "${dockerfile}" .dockerignore docker-compose.yml .github/workflows/build.yml .github/workflows/image.yml
)"
required="$(sort -u <<<"${required}")"
while IFS= read -r path; do
  [ -n "${path}" ] || continue
  case "${path}" in */) path="${path}**" ;; esac
  if ! covered "${path}"; then
    echo "not covered by the paths of ${workflow}: ${path}" >&2
    failures=$((failures + 1))
  fi
done <<<"${required}"

# What must not build an image.
for path in app/tests/test_x.py app/tests/conftest.py docs/runbook-prod.md web/src/App.tsx \
  infra/prod/lambda.tf .github/workflows/ci.yml README.md; do
  if covered "${path}"; then
    echo "${path} starts a build, but cannot change the image (see the paths of ${workflow})" >&2
    failures=$((failures + 1))
  fi
done

if [ "${failures}" -ne 0 ]; then
  echo "${failures} problem(s)" >&2
  exit 1
fi
echo "the build paths match the image: $(wc -l <<<"${patterns}") paths cover $(wc -l <<<"${required}") required files and folders"
