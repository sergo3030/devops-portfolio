#!/usr/bin/env bash
# The steps of the image build that talk to ECR, kept in one script so they can be tested with
# fake `aws` and `docker` commands (scripts/test-ecr-image.sh) before the workflow ever runs them.
#
#   ecr-image.sh lookup   is there already an image for this commit? (found=true|false)
#   ecr-image.sh push     log in, tag the locally built image and push it
#   ecr-image.sh report   read the pushed image back from ECR: digest, tag, manifest type
#
# Environment: ECR_REPOSITORY, AWS_REGION, GIT_SHA (40 hex characters), and for `push`
# ECR_REGISTRY. LOCAL_IMAGE is the image the smoke test passed (default portfolio-api:ci).
# Results go to $GITHUB_OUTPUT (stdout when it is not set).
#
# Tags are immutable in the repository, and the only tag is sha-<commit>. An image that already
# has the tag is reused, never rebuilt: builds are not bit-for-bit reproducible, so the first
# image pushed for a commit stays the one that is deployed.
set -euo pipefail

repository="${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
region="${AWS_REGION:?AWS_REGION is required}"
sha="${GIT_SHA:?GIT_SHA is required}"
local_image="${LOCAL_IMAGE:-portfolio-api:ci}"
out="${GITHUB_OUTPUT:-/dev/stdout}"

if ! [[ "${sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "GIT_SHA must be a full 40-character commit hash" >&2
  exit 1
fi
tag="sha-${sha}"

# Prints "<digest> <manifest media type>". Returns 3 when the tag does not exist, and 1 for any
# other failure (no permission, no network), which must not be mistaken for "not found".
describe() {
  local err result
  err="$(mktemp)"
  if result="$(aws ecr describe-images --region "${region}" --repository-name "${repository}" \
    --image-ids "imageTag=${tag}" \
    --query 'imageDetails[0].[imageDigest,imageManifestMediaType]' --output text 2>"${err}")"; then
    rm -f "${err}"
    echo "${result}"
    return 0
  fi
  if grep -q 'ImageNotFoundException' "${err}"; then
    rm -f "${err}"
    return 3
  fi
  cat "${err}" >&2
  rm -f "${err}"
  return 1
}

lookup() {
  local status=0
  describe >/dev/null || status=$?
  case "${status}" in
    0) echo "found=true" >>"${out}" ;;
    3) echo "found=false" >>"${out}" ;;
    *) echo "could not look up ${repository}:${tag}" >&2; exit 1 ;;
  esac
}

push() {
  local registry="${ECR_REGISTRY:?ECR_REGISTRY is required for push}"
  aws ecr get-login-password --region "${region}" \
    | docker login --username AWS --password-stdin "${registry}" >/dev/null
  docker tag "${local_image}" "${registry}/${repository}:${tag}"
  docker push --quiet "${registry}/${repository}:${tag}" >/dev/null
}

report() {
  local line digest media
  line="$(describe)" || { echo "${repository}:${tag} is not in ECR" >&2; exit 1; }
  read -r digest media <<<"${line}"
  if ! [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "ECR returned an unexpected digest" >&2
    exit 1
  fi
  # Lambda rejects an image index (a multi-platform or attested build). It must be one manifest.
  case "${media}" in
    *index* | *list*)
      echo "the image is a manifest list or index (${media}), which Lambda cannot run" >&2
      exit 1
      ;;
  esac
  {
    echo "digest=${digest}"
    echo "tag=${tag}"
    echo "media_type=${media}"
  } >>"${out}"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### Image in ECR"
      echo "- tag: \`${tag}\`"
      echo "- digest: \`${digest}\`"
      echo "- manifest: \`${media}\`"
    } >>"${GITHUB_STEP_SUMMARY}"
  fi
}

case "${1:-}" in
  lookup) lookup ;;
  push) push ;;
  report) report ;;
  *) echo "usage: ecr-image.sh lookup|push|report" >&2; exit 2 ;;
esac
