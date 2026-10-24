#!/usr/bin/env bash
# Finds the commit an image in ECR was built from, given its digest, so that a deploy can check
# that the running API reports exactly that commit.
#
#   image-commit.sh <sha256:digest>     writes commit=<40 hex> to $GITHUB_OUTPUT (stdout if unset)
#
# The build tags every image sha-<commit> (and only that), so the commit is read from the tag.
# It fails for a digest that is not in the repository or has no such tag, which also makes a
# mistyped or foreign digest a clear error before anything is planned.
# Environment: ECR_REPOSITORY, AWS_REGION.
set -euo pipefail

digest="${1:?usage: image-commit.sh <sha256:digest>}"
repository="${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
region="${AWS_REGION:?AWS_REGION is required}"
out="${GITHUB_OUTPUT:-/dev/stdout}"

if ! [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "the digest must look like sha256:<64 hex characters>" >&2
  exit 1
fi

err="$(mktemp)"
trap 'rm -f "${err}"' EXIT

if ! tags="$(aws ecr describe-images --region "${region}" --repository-name "${repository}" \
  --image-ids "imageDigest=${digest}" --query 'imageDetails[0].imageTags' --output text 2>"${err}")"; then
  if grep -q 'ImageNotFoundException' "${err}"; then
    echo "${digest} is not an image in ${repository}" >&2
  else
    cat "${err}" >&2
  fi
  exit 1
fi

for tag in ${tags}; do
  if [[ "${tag}" =~ ^sha-([0-9a-f]{40})$ ]]; then
    echo "commit=${BASH_REMATCH[1]}" >>"${out}"
    exit 0
  fi
done

echo "${digest} has no sha-<commit> tag, so the commit it was built from is unknown" >&2
exit 1
