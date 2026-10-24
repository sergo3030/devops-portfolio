#!/usr/bin/env bash
# Finds the commit and the version an image in ECR was built from, given its digest, so that a
# deploy can check that the running API reports exactly that commit and version.
#
#   image-commit.sh <sha256:digest>     writes commit=<40 hex> and version=<x.y.z> to $GITHUB_OUTPUT
#                                       (stdout if unset)
#
# The build tags every image sha-<commit>, and a release also sha-<commit>-v<x.y.z>, so both are
# read from the tags: an image with only sha-<commit> is a development build (0.0.0-dev).
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

# A release tag (with the version) wins over a plain commit tag if an image ever had both.
found=""
for tag in ${tags}; do
  if [[ "${tag}" =~ ^sha-([0-9a-f]{40})-v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    found="commit=${BASH_REMATCH[1]}"$'\n'"version=${BASH_REMATCH[2]}"
    break
  fi
  if [[ "${tag}" =~ ^sha-([0-9a-f]{40})$ ]]; then
    found="commit=${BASH_REMATCH[1]}"$'\n'"version=0.0.0-dev"
  fi
done

if [ -z "${found}" ]; then
  echo "${digest} has no sha-<commit> tag, so the commit it was built from is unknown" >&2
  exit 1
fi
echo "${found}" >>"${out}"
