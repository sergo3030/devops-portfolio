#!/usr/bin/env bash
# Checks that a release is allowed before anything is built or published.
#
#   check-release.sh <version> <commit>
#
# - the version is x.y.z (digits, no leading zeros, no v and no suffix),
# - the git tag v<version> exists and points at exactly this commit,
# - the commit is on the main branch, so only code that passed the pull-request checks is released.
# Run it in a checkout with the tags and the history of main (fetch-depth 0).
# MAIN_REF is the ref of main to compare with (default origin/main).
set -euo pipefail

version="${1:?usage: check-release.sh <version> <commit>}"
commit="${2:?usage: check-release.sh <version> <commit>}"
main_ref="${MAIN_REF:-origin/main}"

fail() { echo "release refused: $*" >&2; exit 1; }

number='(0|[1-9][0-9]*)'
[[ "${version}" =~ ^${number}\.${number}\.${number}$ ]] \
  || fail "the version '${version}' must look like 1.2.3 (digits only, no leading zeros, no v, no suffix)"
[[ "${commit}" =~ ^[0-9a-f]{40}$ ]] || fail "the commit must be a full 40-character hash"

tagged="$(git rev-parse -q --verify "refs/tags/v${version}^{commit}")" \
  || fail "the tag v${version} does not exist (push it first)"
[ "${tagged}" = "${commit}" ] \
  || fail "the tag v${version} points at ${tagged}, not at ${commit}"

git rev-parse -q --verify "${main_ref}^{commit}" >/dev/null \
  || fail "cannot find ${main_ref} (fetch the history of main)"
git merge-base --is-ancestor "${commit}" "${main_ref}" \
  || fail "commit ${commit} is not on main: only commits that passed the pull-request checks can be released"

echo "release v${version} at ${commit} is allowed"
