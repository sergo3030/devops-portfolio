#!/usr/bin/env bash
# Tests scripts/verify-clean.sh with fixtures (VERIFY_CLEAN_INPUT) and with a fake `aws`. Run from
# the repository root. No AWS account is used.
set -euo pipefail

script="$(pwd)/scripts/verify-clean.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

T=$'\t'
bootstrap="s3${T}portfolio-tfstate-abc123
iam-role${T}portfolio-plan
iam-role${T}portfolio-ecr-push
iam-role${T}portfolio-apply
iam-policy${T}portfolio-boundary
oidc${T}token.actions.githubusercontent.com
budget${T}portfolio-monthly-1usd
budget${T}portfolio-alert-test
tagged${T}arn:aws:s3:::portfolio-tfstate-abc123
tagged${T}arn:aws:iam::123456789012:role/portfolio-plan
tagged${T}arn:aws:iam::123456789012:policy/portfolio-boundary
tagged${T}arn:aws:budgets::123456789012:budget/portfolio-monthly-1usd
tagged${T}arn:aws:ce::123456789012:anomalymonitor/0000-1111"

run() { # <name> <expected-exit> <level> <fixture-content> [expected output text]
  local name="$1" want="$2" level="$3" content="$4" text="${5:-}" got=0
  printf '%s\n' "${content}" >"${work}/fixture"
  VERIFY_CLEAN_INPUT="${work}/fixture" bash "${script}" "${level}" >"${work}/out" 2>&1 || got=$?
  if [ "${got}" != "${want}" ]; then
    fail "${name} (exit ${got}, wanted ${want}): $(cat "${work}/out")"
  elif [ -n "${text}" ] && ! grep -qF "${text}" "${work}/out"; then
    fail "${name}: output does not say '${text}': $(cat "${work}/out")"
  else
    pass "${name}"
  fi
}

run "level1: only the bootstrap root remains" 0 level1 "${bootstrap}" "only the bootstrap root remains (13 items)"
run "level1: nothing at all is fine too" 0 level1 "" "only the bootstrap root remains (0 items)"
run "level2: nothing remains" 0 level2 "" "nothing tagged or named portfolio-* remains"
run "level2 is the default" 0 level2 "" "clean at level2"

run "level1: a Lambda function is left" 1 level1 "${bootstrap}
lambda${T}portfolio-api" "lambda: portfolio-api"
run "level1: the ECR repository is left" 1 level1 "ecr${T}portfolio-api" "ecr: portfolio-api"
run "level1: the log group is left" 1 level1 "log-group${T}/aws/lambda/portfolio-api" "log-group: /aws/lambda/portfolio-api"
run "level1: the prod role is left" 1 level1 "iam-role${T}portfolio-prod-lambda" "iam-role: portfolio-prod-lambda"
run "level1: a DynamoDB table is left" 1 level1 "dynamodb${T}portfolio-things" "dynamodb: portfolio-things"
run "level1: a second bucket is left" 1 level1 "s3${T}portfolio-other" "s3: portfolio-other"
run "level1: a tagged resource nobody listed is left" 1 level1 "${bootstrap}
tagged${T}arn:aws:ec2:us-east-1:123456789012:natgateway/nat-0abc" "natgateway"
run "level1: a tagged prod function is left" 1 level1 "tagged${T}arn:aws:lambda:us-east-1:123456789012:function:portfolio-api" "function:portfolio-api"
run "level1: every leftover is listed, not only the first" 1 level1 "lambda${T}portfolio-api
ecr${T}portfolio-api" "ecr: portfolio-api"

run "level2: the bootstrap root still exists" 1 level2 "${bootstrap}" "iam-role: portfolio-plan"
run "level2: the state bucket is left" 1 level2 "s3${T}portfolio-tfstate-abc123" "s3: portfolio-tfstate-abc123"
run "level2: the OIDC provider is left" 1 level2 "oidc${T}token.actions.githubusercontent.com" "oidc: token.actions.githubusercontent.com"
run "level2: the Budget is left" 1 level2 "budget${T}portfolio-monthly-1usd" "budget: portfolio-monthly-1usd"

# Bad arguments.
got=0
bash "${script}" level9 >/dev/null 2>&1 || got=$?
if [ "${got}" = 2 ]; then pass "an unknown level is refused"; else fail "an unknown level exited ${got}"; fi

# A failing AWS call must not read as "clean". The fake aws fails on `iam list-roles` only.
mkdir "${work}/bin"
cat >"${work}/bin/aws" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"sts get-caller-identity"*) echo 123456789012 ;;
  *"iam list-roles"*) echo "An error occurred (AccessDenied)" >&2; exit 254 ;;
  *) ;;  # every other list is empty
esac
FAKE
chmod +x "${work}/bin/aws"
got=0
PATH="${work}/bin:${PATH}" bash "${script}" level2 >"${work}/out" 2>&1 || got=$?
if [ "${got}" != 0 ] && ! grep -q "clean at" "${work}/out"; then
  pass "a failing AWS call fails the check instead of reporting clean"
else
  fail "a failing AWS call was reported as clean (exit ${got}): $(cat "${work}/out")"
fi

# With every call answering and nothing there, the check is clean.
cat >"${work}/bin/aws" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"sts get-caller-identity"*) echo 123456789012 ;;
  *) echo "None" ;;  # what the CLI prints for an empty text list
esac
FAKE
got=0
PATH="${work}/bin:${PATH}" bash "${script}" level2 >"${work}/out" 2>&1 || got=$?
if [ "${got}" = 0 ] && grep -q "clean at level2" "${work}/out"; then
  pass "empty answers (and the CLI's 'None') are clean"
else
  fail "empty answers were not clean (exit ${got}): $(cat "${work}/out")"
fi

[ "${failures}" -eq 0 ] || { echo "${failures} failure(s)" >&2; exit 1; }
echo "all tests passed"
