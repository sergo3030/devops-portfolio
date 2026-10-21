#!/usr/bin/env bash
# Every job of the CI and dependency-review workflows must be a required check in
# the main-branch ruleset. A renamed or new job that is missing there would block
# every pull request (or silently go unrequired), so this runs in CI.
set -euo pipefail

ruleset="infra/github/ruleset.tf"
status=0

while IFS= read -r name; do
  if ! grep -qF "\"${name}\"" "${ruleset}"; then
    echo "job '${name}' is not listed as a required check in ${ruleset}" >&2
    status=1
  fi
done < <(grep -h '^    name: ' .github/workflows/ci.yml .github/workflows/dependency-review.yml | sed 's/^    name: //')

# CodeQL job names come from a matrix, so check the languages explicitly.
for language in python actions javascript-typescript; do
  if ! grep -qF "\"analyze (${language})\"" "${ruleset}"; then
    echo "job 'analyze (${language})' is not listed as a required check in ${ruleset}" >&2
    status=1
  fi
done

[ "${status}" -eq 0 ] && echo "required checks match the CI job names"
exit "${status}"
