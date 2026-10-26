#!/usr/bin/env bash
# Level 2: remove AWS. Level 1 first, then the bootstrap root: state bucket, OIDC provider, roles,
# permission boundary, Budgets and the anomaly monitor. The repository and the site stay.
#
#   teardown-aws.sh [preview|apply]     (preview is the default and changes nothing)
#
# preview  requires `verify-clean level1` to pass (so prod is already gone), then prints the full
#          `plan -destroy` of the bootstrap root with force_destroy on, and the steps apply would run.
# apply    needs a terminal. In order: back up the state of the github root (it lives in the bucket
#          that is about to be destroyed, together with the other roots' states), move the bootstrap
#          state back to a local file, apply force_destroy (so the bucket can be emptied), show the
#          destroy plan, destroy only after you type "destroy bootstrap", then verify-clean level2.
#          Run for real on 2026-10-26 (task 20a): 19 resources destroyed in about three minutes.
#          If it stops after the state move, the state is in infra/bootstrap/terraform.tfstate:
#          keep that file. The github backup is infra/github/state-backup.tfstate (gitignored,
#          it holds the account ID): restore it after the rebuild (docs/runbook-bootstrap.md).
#
# Needs `aws login --profile portfolio-bootstrap` and TF_VAR_budget_alert_email (the plan needs it).
# If the account had a GitHub OIDC provider before this project, set create_oidc_provider=false
# first: the provider is account-wide.
set -euo pipefail

# shellcheck source=scripts/teardown-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/teardown-lib.sh"
cd "${repo_root}"

mode="${1:-preview}"
case "${mode}" in preview | apply) ;; *)
  echo "usage: teardown-aws.sh [preview|apply]" >&2
  exit 2
  ;;
esac

root="infra/bootstrap"

require_admin_session
[ -n "${TF_VAR_budget_alert_email:-}" ] ||
  die "TF_VAR_budget_alert_email is not set. The plan needs it (it is never stored in the repository)."

heading "Precondition: Level 1 is done"
bash scripts/verify-clean.sh level1 || die "the prod root is not gone. Run: just teardown-api apply"

if [ "${mode}" = preview ]; then
  trap 'rm -f "${root}/tfplan-destroy"' EXIT
  tofu -chdir="${root}" init -input=false -no-color >/dev/null
  heading "plan -destroy of the bootstrap root (force_destroy on, so the state bucket can be emptied)"
  plan_and_show "${root}" tfplan-destroy -destroy -var force_destroy=true
  heading "Nothing was applied"
  say "apply would: 0) back up the state of the github root, 1) move the state back to a local file,"
  say "2) apply force_destroy=true, 3) plan -destroy again and show it, 4) destroy after you type"
  say "\"destroy bootstrap\", 5) run verify-clean level2. Then (by hand): aws logout, delete the portfolio-admin user if you"
  say "are leaving for good, remove the local state files. See docs/runbook-prod.md, Level 2."
  exit 0
fi

require_terminal
say "This removes every AWS resource of the project, including the state bucket and the roles CI uses."
confirm_phrase "remove aws"

# The github and prod roots keep their states in the same bucket, so destroying it destroys them too.
# Prod is already gone (Level 1); the github root manages the repository's settings and has to be
# restored after a rebuild, so its state is copied out first. A file that is empty or not a state
# stops the run before anything is changed.
heading "0. Back up the state of the github root"
github_backup="infra/github/state-backup.tfstate"
tofu -chdir=infra/github init -input=false -no-color >/dev/null
if ! tofu -chdir=infra/github state pull >"${github_backup}" || ! grep -q '"lineage"' "${github_backup}"; then
  rm -f "${github_backup}"
  die "the github state could not be read, so nothing was changed."
fi
say "saved ${github_backup} ($(wc -c <"${github_backup}" | tr -d ' ') bytes). Restore it after the rebuild; it holds the account ID."

backend="${root}/backend.tf"
[ -f "${backend}" ] || die "${backend} is missing: the state is not in the bucket, or a previous run stopped half way."
trap 'rm -f "${root}/tfplan-force" "${root}/tfplan-destroy"; if [ -f "${backend}.off" ]; then mv -f "${backend}.off" "${backend}"; fi' EXIT
mv "${backend}" "${backend}.off"

heading "1. Move the state back to a local file"
tofu -chdir="${root}" init -migrate-state -force-copy -input=false -no-color

heading "2. Allow the state bucket to be emptied (force_destroy)"
plan_and_show "${root}" tfplan-force -var force_destroy=true
ask_yes "Apply this?"
tofu -chdir="${root}" apply -input=false -no-color tfplan-force

heading "3. Destroy"
plan_and_show "${root}" tfplan-destroy -destroy -var force_destroy=true
confirm_phrase "destroy bootstrap"
tofu -chdir="${root}" apply -input=false -no-color tfplan-destroy

heading "4. Verify"
bash scripts/verify-clean.sh level2
say ""
say "Left for you: aws logout, delete the portfolio-admin IAM user (only if you are leaving the project),"
say "delete ${root}/terraform.tfstate* (it holds the alert email), and check the bill tomorrow."
say "To rebuild instead, follow \"Rebuilding after Level 2\" in docs/runbook-bootstrap.md and keep ${github_backup}."
