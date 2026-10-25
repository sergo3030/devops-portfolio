#!/usr/bin/env bash
# Tests the guards and the order of steps in teardown-api.sh, teardown-aws.sh and up-prod.sh with
# fake `aws`, `tofu` and `gh` commands that only record what they were asked to do. The scripts run
# from a copy of the repository layout in a temporary directory. No AWS account is used. Run from
# the repository root.
#
# What this proves: a preview applies nothing, an apply needs a terminal and the typed phrase,
# the steps run in the documented order, and nothing starts without the admin session. What it
# cannot prove is what the real tools do: that is what the rehearsal is for.
set -euo pipefail

repo="$(pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

# The layout the scripts expect, with copies of the scripts under test.
mkdir -p "${work}/repo/scripts" "${work}/repo/infra/prod" "${work}/repo/infra/bootstrap" "${work}/bin"
cp "${repo}"/scripts/{teardown-lib,teardown-api,teardown-aws,up-prod,verify-clean}.sh "${work}/repo/scripts/"
echo '# backend' >"${work}/repo/infra/bootstrap/backend.tf"

cat >"${work}/bin/aws" <<'FAKE'
#!/usr/bin/env bash
echo "aws $*" >>"${LOG}"
case "$*" in
  *"sts get-caller-identity"*) echo "${FAKE_ARN:-arn:aws:iam::123456789012:user/portfolio-admin}" ;;
esac
FAKE
cat >"${work}/bin/tofu" <<'FAKE'
#!/usr/bin/env bash
echo "tofu $*" >>"${LOG}"
case "$*" in
  *" output "*) [ -n "${FAKE_DIGEST:-}" ] && printf '%s' "${FAKE_DIGEST}" || exit 1 ;;
  *" show "*) echo "RENDERED PLAN ${*: -1}" ;;
esac
FAKE
cat >"${work}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
echo "gh $*" >>"${LOG}"
FAKE
chmod +x "${work}/bin/aws" "${work}/bin/tofu" "${work}/bin/gh"

T=$'\t'
printf 's3%sportfolio-tfstate-abc123\niam-role%sportfolio-plan\n' "${T}" "${T}" >"${work}/bootstrap-only"
printf 'lambda%sportfolio-api\n' "${T}" >"${work}/with-lambda"

DIGEST="sha256:$(printf 'a%.0s' $(seq 1 64))"

# run <name> <script> <mode> <stdin> -- env assignments...   (sets: code, out, and the call log)
run() {
  local script="$2" mode="$3" input="$4"
  shift 5
  : >"${work}/log"
  code=0
  # shellcheck disable=SC2154 # PATH is set by the caller
  env PATH="${work}/bin:${PATH}" LOG="${work}/log" TEARDOWN_ALLOW_PIPE=1 \
    VERIFY_CLEAN_INPUT="${work}/bootstrap-only" TF_VAR_budget_alert_email=a@example.com "$@" \
    bash "${work}/repo/scripts/${script}" "${mode}" <<<"${input}" >"${work}/out" 2>&1 || code=$?
}
called() { grep -qE "$1" "${work}/log"; }
check() { # <name> <condition: 0 = true>
  if [ "$2" = 0 ]; then pass "$1"; else fail "$1"$'\n'"--- output:"$'\n'"$(cat "${work}/out")"$'\n'"--- log:"$'\n'"$(cat "${work}/log")"; fi
}

# ------------------------------------------------------------------ teardown-api.sh

run x teardown-api.sh preview "" -- FAKE_DIGEST="${DIGEST}"
check "api preview succeeds" "$([ "${code}" = 0 ] && echo 0 || echo 1)"
check "api preview applies nothing" "$(called 'tofu .* apply' && echo 1 || echo 0)"
check "api preview plans the force_delete step and the destroy, with the deployed digest" \
  "$(called "plan .*-var force_delete_images=true .*-var image_digest=${DIGEST}" && called 'plan .*-destroy' && echo 0 || echo 1)"
check "api preview shows the rendered plans" "$(grep -q 'RENDERED PLAN tfplan-destroy' "${work}/out" && echo 0 || echo 1)"
check "api preview does not touch GitHub" "$(called '^gh ' && echo 1 || echo 0)"

run x teardown-api.sh preview "" -- FAKE_DIGEST=""
check "api preview works when no function is deployed (no digest variable)" \
  "$([ "${code}" = 0 ] && ! called '-var image_digest' && echo 0 || echo 1)"

run x teardown-api.sh preview "" -- FAKE_ARN="arn:aws:iam::123456789012:root"
check "api refuses the root session before any tofu call" "$([ "${code}" != 0 ] && ! called '^tofu ' && echo 0 || echo 1)"

run x teardown-api.sh nonsense "" --
check "api refuses an unknown mode" "$([ "${code}" = 2 ] && echo 0 || echo 1)"

run x teardown-api.sh apply "y"$'\n'"destroy prod" -- FAKE_DIGEST="${DIGEST}" TEARDOWN_ALLOW_PIPE=0
check "api apply refuses without a terminal" "$([ "${code}" != 0 ] && ! called 'tofu .* apply' && grep -q 'needs a terminal' "${work}/out" && echo 0 || echo 1)"

run x teardown-api.sh apply "y"$'\n'"destroy prod" -- FAKE_DIGEST="${DIGEST}"
check "api apply succeeds with both confirmations" "$([ "${code}" = 0 ] && echo 0 || echo 1)"
check "api apply: force_delete first, then a fresh destroy plan, then the destroy" \
  "$(awk '/apply .*tfplan-force/{a=NR} /plan .*-destroy/{p=NR} /apply .*tfplan-destroy/{d=NR} END{exit !(a && p>a && d>p)}' "${work}/log" && echo 0 || echo 1)"
check "api apply disables the synthetic workflow after the destroy" \
  "$(awk '/apply .*tfplan-destroy/{d=NR} /gh workflow disable synthetic.yml/{g=NR} END{exit !(d && g>d)}' "${work}/log" && echo 0 || echo 1)"
check "api apply ends with verify-clean at level1" "$(grep -q 'clean at level1' "${work}/out" && echo 0 || echo 1)"

run x teardown-api.sh apply "y"$'\n'"yes please" -- FAKE_DIGEST="${DIGEST}"
check "api apply: a wrong phrase stops before the destroy" \
  "$([ "${code}" != 0 ] && called 'apply .*tfplan-force' && ! called 'apply .*tfplan-destroy' && ! called 'gh workflow disable' && echo 0 || echo 1)"

run x teardown-api.sh apply "n" -- FAKE_DIGEST="${DIGEST}"
check "api apply: answering no to step 1 changes nothing" "$([ "${code}" != 0 ] && ! called 'tofu .* apply' && echo 0 || echo 1)"

run x teardown-api.sh apply "y"$'\n'"destroy prod" -- FAKE_DIGEST="${DIGEST}" VERIFY_CLEAN_INPUT="${work}/with-lambda"
check "api apply fails loudly when something is left behind" "$([ "${code}" != 0 ] && grep -q 'lambda: portfolio-api' "${work}/out" && echo 0 || echo 1)"

# ------------------------------------------------------------------ teardown-aws.sh

run x teardown-aws.sh preview "" --
check "aws preview succeeds when Level 1 is done" "$([ "${code}" = 0 ] && echo 0 || echo 1)"
check "aws preview plans the destroy with force_destroy and applies nothing" \
  "$(called 'plan .*-destroy .*-var force_destroy=true' && ! called 'tofu .* apply' && ! called 'migrate-state' && echo 0 || echo 1)"
check "aws preview leaves backend.tf alone" "$([ -f "${work}/repo/infra/bootstrap/backend.tf" ] && echo 0 || echo 1)"

run x teardown-aws.sh preview "" -- VERIFY_CLEAN_INPUT="${work}/with-lambda"
check "aws preview refuses while prod still exists, before any plan" \
  "$([ "${code}" != 0 ] && ! called 'tofu .*plan' && grep -q 'just teardown-api' "${work}/out" && echo 0 || echo 1)"

run x teardown-aws.sh preview "" -- TF_VAR_budget_alert_email=
check "aws preview needs the alert email variable" "$([ "${code}" != 0 ] && grep -q 'TF_VAR_budget_alert_email' "${work}/out" && echo 0 || echo 1)"

run x teardown-aws.sh apply "remove aws"$'\n'"y"$'\n'"destroy bootstrap" -- VERIFY_CLEAN_INPUT="${work}/bootstrap-only"
# After the destroy verify-clean level2 runs against the same fixture, which still lists the
# bootstrap items, so the run ends non-zero: that is the check doing its job.
check "aws apply runs: state move, force_destroy apply, fresh destroy plan, destroy" \
  "$(awk '/migrate-state/{m=NR} /apply .*tfplan-force/{a=NR} /plan .*-destroy/{p=NR} /apply .*tfplan-destroy/{d=NR} END{exit !(m && a>m && p>a && d>p)}' "${work}/log" && echo 0 || echo 1)"
check "aws apply puts backend.tf back" "$([ -f "${work}/repo/infra/bootstrap/backend.tf" ] && [ ! -f "${work}/repo/infra/bootstrap/backend.tf.off" ] && echo 0 || echo 1)"
check "aws apply ends with verify-clean at level2" "$(grep -q 'NOT CLEAN at level2' "${work}/out" && echo 0 || echo 1)"

run x teardown-aws.sh apply "remove aws"$'\n'"y"$'\n'"nope" --
check "aws apply: a wrong final phrase stops before the destroy" \
  "$([ "${code}" != 0 ] && ! called 'apply .*tfplan-destroy' && [ -f "${work}/repo/infra/bootstrap/backend.tf" ] && echo 0 || echo 1)"

run x teardown-aws.sh apply "no" --
check "aws apply: the first phrase is required before anything moves" \
  "$([ "${code}" != 0 ] && ! called 'migrate-state' && echo 0 || echo 1)"

run x teardown-aws.sh apply "remove aws" -- TEARDOWN_ALLOW_PIPE=0
check "aws apply refuses without a terminal" "$([ "${code}" != 0 ] && ! called 'migrate-state' && echo 0 || echo 1)"

# ------------------------------------------------------------------ up-prod.sh

run x up-prod.sh preview "" -- FAKE_DIGEST=""
check "up preview prints phase 1 and applies nothing" \
  "$([ "${code}" = 0 ] && ! called 'tofu .* apply' && ! called '^gh ' && grep -q 'RENDERED PLAN tfplan-phase1' "${work}/out" && echo 0 || echo 1)"

run x up-prod.sh preview "" -- FAKE_DIGEST="${DIGEST}"
check "up refuses when production is already up (a plan without a digest would remove the function)" \
  "$([ "${code}" != 0 ] && grep -q 'already up' "${work}/out" && ! called 'tofu .*plan' && echo 0 || echo 1)"

run x up-prod.sh apply "y" -- FAKE_DIGEST="" TEARDOWN_ALLOW_PIPE=0
check "up apply refuses without a terminal" "$([ "${code}" != 0 ] && ! called 'tofu .* apply' && echo 0 || echo 1)"

run x up-prod.sh apply "n" -- FAKE_DIGEST=""
check "up apply: answering no to phase 1 changes nothing" "$([ "${code}" != 0 ] && ! called 'tofu .* apply' && ! called '^gh ' && echo 0 || echo 1)"

[ "${failures}" -eq 0 ] || { echo "${failures} failure(s)" >&2; exit 1; }
echo "all tests passed"
