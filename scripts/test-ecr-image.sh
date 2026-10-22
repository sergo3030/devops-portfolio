#!/usr/bin/env bash
# Tests scripts/ecr-image.sh with fake `aws` and `docker` commands, so the logic around ECR
# (immutable tags, not-found versus real errors, the manifest check) is checked in CI and on a
# laptop without any AWS access or Docker. Run from the repository root.
set -euo pipefail

script="$(pwd)/scripts/ecr-image.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/bin"

sha="0123456789abcdef0123456789abcdef01234567"
digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# Fake aws. FAKE_AWS_MODE picks the answer to `ecr describe-images`.
cat >"${work}/bin/aws" <<'EOF'
#!/usr/bin/env bash
echo "aws $*" >>"${FAKE_LOG}"
case "$1 $2" in
  "ecr describe-images")
    case "${FAKE_AWS_MODE}" in
      found) printf '%s\t%s\n' "${FAKE_DIGEST}" "application/vnd.oci.image.manifest.v1+json" ;;
      docker_manifest) printf '%s\t%s\n' "${FAKE_DIGEST}" "application/vnd.docker.distribution.manifest.v2+json" ;;
      index) printf '%s\t%s\n' "${FAKE_DIGEST}" "application/vnd.oci.image.index.v1+json" ;;
      badsha) printf '%s\t%s\n' "sha256:short" "application/vnd.oci.image.manifest.v1+json" ;;
      missing)
        echo "An error occurred (ImageNotFoundException) when calling the DescribeImages operation: The image with imageId {imageTag:sha-x} does not exist" >&2
        exit 254
        ;;
      denied)
        echo "An error occurred (AccessDeniedException) when calling the DescribeImages operation: not authorized" >&2
        exit 254
        ;;
    esac
    ;;
  "ecr get-login-password") echo "fake-password" ;;
esac
EOF

# Fake docker: records the call, and reads stdin for `login`.
cat >"${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"${FAKE_LOG}"
if [ "$1" = login ]; then cat >/dev/null; fi
EOF
chmod +x "${work}/bin/aws" "${work}/bin/docker"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

# run <mode> <command> [extra env assignments...]: runs the script, leaves output in $work/out
# and the fake commands' log in $work/log, and sets $status.
run() {
  local mode="$1" command="$2"
  shift 2
  : >"${work}/log"
  : >"${work}/out"
  status=0
  env PATH="${work}/bin:${PATH}" FAKE_LOG="${work}/log" FAKE_AWS_MODE="${mode}" FAKE_DIGEST="${digest}" \
    ECR_REPOSITORY=portfolio-api AWS_REGION=us-east-1 GIT_SHA="${sha}" GITHUB_OUTPUT="${work}/out" \
    "$@" bash "${script}" "${command}" 2>"${work}/err" || status=$?
}

run found lookup
if [ "${status}" -eq 0 ] && grep -qx 'found=true' "${work}/out"; then pass "lookup finds an existing image"; else fail "lookup should report found=true"; fi

run missing lookup
if [ "${status}" -eq 0 ] && grep -qx 'found=false' "${work}/out"; then pass "lookup reports a missing tag as found=false"; else fail "lookup should report found=false"; fi

run denied lookup
if [ "${status}" -ne 0 ] && ! grep -q 'found=' "${work}/out"; then pass "lookup fails on a real error instead of treating it as not found"; else fail "an access error must not look like a missing image"; fi

run found lookup GIT_SHA=main
if [ "${status}" -ne 0 ]; then pass "a GIT_SHA that is not a full commit hash is rejected"; else fail "short or symbolic GIT_SHA must be rejected"; fi

run found report GITHUB_STEP_SUMMARY="${work}/summary"
if [ "${status}" -eq 0 ] && grep -qx "digest=${digest}" "${work}/out" && grep -qx "tag=sha-${sha}" "${work}/out" && grep -q "${digest}" "${work}/summary"; then
  pass "report writes the digest and tag to the outputs and the summary"
else fail "report should output the digest and tag"; fi

run docker_manifest report
if [ "${status}" -eq 0 ]; then pass "a Docker v2 manifest is accepted"; else fail "a Docker v2 manifest must be accepted"; fi

run index report
if [ "${status}" -ne 0 ] && grep -q 'index' "${work}/err"; then pass "an image index is rejected (Lambda cannot run it)"; else fail "an image index must be rejected"; fi

run badsha report
if [ "${status}" -ne 0 ]; then pass "a malformed digest is rejected"; else fail "a malformed digest must be rejected"; fi

run missing report
if [ "${status}" -ne 0 ]; then pass "report fails when the image is not in ECR"; else fail "report must fail for a missing image"; fi

run found push ECR_REGISTRY=123456789012.dkr.ecr.us-east-1.amazonaws.com LOCAL_IMAGE=portfolio-api:ci
expected_ref="123456789012.dkr.ecr.us-east-1.amazonaws.com/portfolio-api:sha-${sha}"
if [ "${status}" -eq 0 ] \
  && grep -q "^docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com" "${work}/log" \
  && grep -qx "docker tag portfolio-api:ci ${expected_ref}" "${work}/log" \
  && grep -qx "docker push --quiet ${expected_ref}" "${work}/log"; then
  pass "push logs in, tags the smoke-tested image with sha-<commit> and pushes that tag"
else fail "push should log in, tag and push the commit tag"; fi

if ! grep -q ':latest' "${work}/log"; then pass "no moving tag (latest) is ever pushed"; else fail "a latest tag must never be pushed"; fi

run found push
if [ "${status}" -ne 0 ]; then pass "push without a registry is refused"; else fail "push needs ECR_REGISTRY"; fi

if [ "${failures}" -ne 0 ]; then
  echo "${failures} test(s) failed" >&2
  exit 1
fi
echo "all ecr-image tests passed"
