#!/usr/bin/env bash
# Tests scripts/check-release.sh against a real, temporary git repository: a release must be a
# plain x.y.z version, whose tag exists and points at the given commit, and that commit must be
# on main. Run from the repository root.
set -euo pipefail

script="$(pwd)/scripts/check-release.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

cd "${work}"
git init -q -b main
git config user.email "test@example.com"
git config user.name "Test"
git config commit.gpgsign false
git config tag.gpgsign false

git commit -q --allow-empty -m "first"
first="$(git rev-parse HEAD)"
git tag v1.0.0

git checkout -q -b side
git commit -q --allow-empty -m "only on a branch"
side="$(git rev-parse HEAD)"
git tag v1.1.0
git checkout -q main

git commit -q --allow-empty -m "second"
second="$(git rev-parse HEAD)"
git tag -a v2.0.0 -m "an annotated tag"
git tag v2.0.0-rc1

# Tags that exist and point at a commit of main, so that only the version format can refuse them.
for odd in v01.0.0 v1.0 v1.0.0.0 v1.0.0-rc1 vabc; do git tag "${odd}" "${first}"; done

check() { # <version> <commit>
  status=0
  MAIN_REF=main bash "${script}" "$1" "$2" >"${work}.out" 2>&1 || status=$?
}

check 1.0.0 "${first}"
if [ "${status}" -eq 0 ]; then pass "a tag on a commit of main is allowed"; else fail "v1.0.0 should be allowed"; fi

check 2.0.0 "${second}"
if [ "${status}" -eq 0 ]; then pass "an annotated tag is allowed too"; else fail "v2.0.0 (annotated) should be allowed"; fi

check 1.1.0 "${side}"
if [ "${status}" -ne 0 ] && grep -q 'not on main' "${work}.out"; then pass "a commit that is not on main is refused"; else fail "a branch-only commit must be refused"; fi

check 1.0.0 "${second}"
if [ "${status}" -ne 0 ] && grep -q 'points at' "${work}.out"; then pass "a tag that points at another commit is refused"; else fail "a tag/commit mismatch must be refused"; fi

check 3.0.0 "${second}"
if [ "${status}" -ne 0 ] && grep -q 'does not exist' "${work}.out"; then pass "a missing tag is refused"; else fail "a missing tag must be refused"; fi

for bad in v1.0.0 1.0 01.0.0 1.0.0.0 1.0.0-rc1 "1.0.0 " "" abc; do
  check "${bad}" "${first}"
  if [ "${status}" -ne 0 ]; then :; else fail "version '${bad}' must be refused"; fi
done
pass "versions that are not plain x.y.z are refused (v prefix, two parts, leading zero, four parts, suffix, blank, text)"

check 2.0.0-rc1 "${second}"
if [ "${status}" -ne 0 ]; then pass "a pre-release suffix is not a release version"; else fail "rc tags are not releases"; fi

check 1.0.0 "main"
if [ "${status}" -ne 0 ] && grep -q '40-character' "${work}.out"; then pass "a branch name is not accepted as the commit"; else fail "the commit must be a full hash"; fi

status=0
MAIN_REF=origin/missing bash "${script}" 1.0.0 "${first}" >"${work}.out" 2>&1 || status=$?
if [ "${status}" -ne 0 ] && grep -q 'cannot find' "${work}.out"; then pass "a missing main history is an error, not a pass"; else fail "no main ref must fail"; fi

rm -f "${work}.out"
if [ "${failures}" -ne 0 ]; then
  echo "${failures} test(s) failed" >&2
  exit 1
fi
echo "all release check tests passed"
