#!/usr/bin/env bash
# Recreates production after `just teardown-api`: phase 1 (repository and the pieces around it),
# an image built by hand through build.yml, phase 2 (function and URL), and the health check.
#
#   up-prod.sh [preview|apply]          (preview is the default and changes nothing)
#
# preview  refuses if production is already up, otherwise prints the phase 1 plan in full.
# apply    needs a terminal. It asks before each apply, starts build.yml on main, takes the new
#          image from ECR, plans phase 2 with its digest and checks /health after the apply.
#          The deploy job that build.yml starts can only fail here (it allows an image swap, not
#          a creation): REJECT its pending approval in the Actions tab.
#          The URL is new: web/.env.production must be changed in a pull request afterwards.
#
# Needs `aws login --profile portfolio-bootstrap`, OpenTofu, gh (logged in) and python3.
set -euo pipefail

# shellcheck source=scripts/teardown-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/teardown-lib.sh"
cd "${repo_root}"

mode="${1:-preview}"
case "${mode}" in preview | apply) ;; *)
  echo "usage: up-prod.sh [preview|apply]" >&2
  exit 2
  ;;
esac

prod="infra/prod"
repository="portfolio-api"
trap 'rm -f "${prod}/tfplan-phase1" "${prod}/tfplan-phase2"' EXIT

require_admin_session
tofu -chdir="${prod}" init -input=false -no-color >/dev/null

current="$(tofu -chdir="${prod}" output -no-color -raw deployed_image_digest 2>/dev/null || true)"
if [[ "${current}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  die "production is already up (running ${current}). To deploy another image use the deploy workflow."
fi

heading "Phase 1: repository, lifecycle policy, log group, role (no function yet)"
plan_and_show "${prod}" tfplan-phase1

if [ "${mode}" = preview ]; then
  heading "Nothing was applied"
  say "apply would: apply phase 1, start build.yml on main, wait for the image, plan phase 2 with its"
  say "digest, apply it after you confirm, and check /health. Then change web/.env.production."
  exit 0
fi

require_terminal
ask_yes "Apply phase 1?"
tofu -chdir="${prod}" apply -input=false -no-color tfplan-phase1

heading "Build the image (build.yml on main)"
latest_run() { gh run list --workflow build.yml --limit 1 --json databaseId --jq '.[0].databaseId // 0'; }
before="$(latest_run)"
gh workflow run build.yml --ref main
run_id="${before}"
for _ in $(seq 1 30); do
  sleep 4
  run_id="$(latest_run)"
  if [ "${run_id}" != "${before}" ]; then break; fi
done
[ "${run_id}" != "${before}" ] || die "the build run did not start. Start build.yml by hand and run this again."
say "build run ${run_id}. Its deploy job will wait for approval: REJECT it (it cannot create the function)."

result=""
for _ in $(seq 1 90); do
  result="$(gh run view "${run_id}" --json jobs --jq '.jobs[] | select(.name | test("build \\(image\\)")) | .conclusion')"
  if [ -n "${result}" ]; then break; fi
  sleep 10
done
[ "${result}" = success ] || die "the image job ended with '${result:-no result}'. If it is a 429 from public.ecr.aws, re-run the failed jobs, then run this again."

digest="$(aws ecr describe-images --repository-name "${repository}" \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageDigest' --output text)"
[[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "could not read the new image digest from ECR."
say "new image: ${digest}"

heading "Phase 2: function, URL and the public statements"
plan_and_show "${prod}" tfplan-phase2 -var "image_digest=${digest}"
ask_yes "Apply phase 2?"
tofu -chdir="${prod}" apply -input=false -no-color tfplan-phase2

url="$(tofu -chdir="${prod}" output -no-color -raw function_url)"
info="$(ECR_REPOSITORY="${repository}" GITHUB_OUTPUT=/dev/stdout bash scripts/image-commit.sh "${digest}")"
commit="$(sed -n 's/^commit=//p' <<<"${info}")"
version="$(sed -n 's/^version=//p' <<<"${info}")"
python="$(command -v python3 || command -v python)"

heading "Check /health"
"${python}" scripts/verify_deploy.py "${url}" "${commit}" "${version}"

heading "Done. Left for you"
say "1. Reject the pending 'deploy' approval of the build run (Actions tab)."
say "2. The URL is new. In a pull request set, in web/.env.production:"
say "     VITE_API_URL=${url%/}"
say "3. After that merges and the site is rebuilt: gh workflow enable synthetic.yml, then run it."
