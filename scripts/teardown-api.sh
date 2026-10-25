#!/usr/bin/env bash
# Level 1: pause the API. Removes the prod root (Lambda function, Function URL, the public-invoke
# statements, the ECR repository with its images, the log group, the function's role) and keeps
# the bootstrap root, the GitHub settings and the static site (which then says "API offline").
#
#   teardown-api.sh [preview|apply]     (preview is the default and changes nothing)
#
# preview  prints both plans in full: switching on force_delete, and the destroy.
# apply    needs a terminal. It applies step 1 (force_delete on, because the repository holds
#          images and cannot be deleted otherwise), plans the destroy again (a plan made before
#          step 1 would be stale), shows it, and destroys only after you type "destroy prod". Then
#          it disables the daily `synthetic` workflow (it would fail every day with the API gone)
#          and runs verify-clean at level1.
#
# Needs `aws login --profile portfolio-bootstrap` (IAM user portfolio-admin) and OpenTofu.
set -euo pipefail

# shellcheck source=scripts/teardown-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/teardown-lib.sh"
cd "${repo_root}"

mode="${1:-preview}"
case "${mode}" in preview | apply) ;; *)
  echo "usage: teardown-api.sh [preview|apply]" >&2
  exit 2
  ;;
esac

prod="infra/prod"
trap 'rm -f "${prod}/tfplan-force" "${prod}/tfplan-destroy"' EXIT

require_admin_session
tofu -chdir="${prod}" init -input=false -no-color >/dev/null

digest="$(tofu -chdir="${prod}" output -no-color -raw deployed_image_digest 2>/dev/null || true)"
vars=(-var force_delete_images=true)
if [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  # Without the deployed digest the first plan would also remove the function.
  vars+=(-var "image_digest=${digest}")
  say "deployed image: ${digest}"
else
  say "no function is deployed: only the repository and the pieces around it exist"
fi

heading "Step 1: switch on force_delete (the repository holds images)"
plan_and_show "${prod}" tfplan-force "${vars[@]}"

if [ "${mode}" = preview ]; then
  heading "Step 2: the destroy (a preview: the real one is planned again after step 1)"
  plan_and_show "${prod}" tfplan-destroy -destroy "${vars[@]}"
  heading "Nothing was applied"
  say "To pause the API for real, run this in your own terminal: just teardown-api apply"
  exit 0
fi

require_terminal
ask_yes "Apply step 1 (force_delete on, one in-place change)?"
tofu -chdir="${prod}" apply -input=false -no-color tfplan-force

heading "Step 2: destroy (planned after step 1)"
plan_and_show "${prod}" tfplan-destroy -destroy "${vars[@]}"
say ""
say "This removes the API and the images. The site keeps working and says \"API offline\"."
say "It also disables the GitHub workflow 'synthetic'. Recreate everything with: just up-prod"
confirm_phrase "destroy prod"
tofu -chdir="${prod}" apply -input=false -no-color tfplan-destroy

heading "Disable the daily live check"
gh workflow disable synthetic.yml || say "WARNING: could not disable synthetic.yml. Disable it by hand (Actions tab)."

heading "Verify"
bash scripts/verify-clean.sh level1
say ""
say "API paused. Merges that change the image fail to push until 'just up-prod' recreates the repository."
