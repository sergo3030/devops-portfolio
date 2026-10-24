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
    # FAKE_TAGS="tag=digest;tag=digest" answers per tag, for the tests of several tags.
    if [ -n "${FAKE_TAGS:-}" ]; then
      want=""
      for a in "$@"; do case "$a" in imageTag=*) want="${a#imageTag=}" ;; esac; done
      if [ -n "${want}" ]; then
        entry="$(printf '%s' "${FAKE_TAGS}" | tr ';' '\n' | grep "^${want}=" || true)"
        if [ -n "${entry}" ]; then
          printf '%s\t%s\n' "${entry#*=}" "application/vnd.docker.distribution.manifest.v2+json"
          exit 0
        fi
        echo "An error occurred (ImageNotFoundException) when calling the DescribeImages operation: not found" >&2
        exit 254
      fi
    fi
    case "${FAKE_AWS_MODE}" in
      by_digest_release) printf 'v1.2.3\tsha-0123456789abcdef0123456789abcdef01234567-v1.2.3\n' ;;
      by_digest_both) printf 'sha-0123456789abcdef0123456789abcdef01234567\tsha-0123456789abcdef0123456789abcdef01234567-v1.2.3\n' ;;
      found) printf '%s\t%s\n' "${FAKE_DIGEST}" "application/vnd.oci.image.manifest.v1+json" ;;
      docker_manifest) printf '%s\t%s\n' "${FAKE_DIGEST}" "application/vnd.docker.distribution.manifest.v2+json" ;;
      index) printf '%s\t%s\n' "${FAKE_DIGEST}" "application/vnd.oci.image.index.v1+json" ;;
      badsha) printf '%s\t%s\n' "sha256:short" "application/vnd.oci.image.manifest.v1+json" ;;
      by_digest) printf 'release-candidate\tsha-0123456789abcdef0123456789abcdef01234567\n' ;;
      by_digest_untagged) echo "None" ;;
      by_digest_wrong_tags) printf 'latest\tsha-short\tv1.2.3\n' ;;
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
  "ecr batch-get-image") echo '{"schemaVersion":2,"fake":"manifest"}' ;;
  "ecr put-image") ;;
  "ecr get-login-password") echo "fake-password" ;;
  "ecr-public get-login-password")
    case "${FAKE_AWS_MODE}" in
      public_denied)
        echo "An error occurred (AccessDeniedException) when calling the GetAuthorizationToken operation: not authorized" >&2
        exit 254
        ;;
      public_empty) ;;
      *) echo "public-secret-token" ;;
    esac
    ;;
esac
EOF

# Fake docker: records the call, keeps what `login` receives on stdin, and fails on demand.
cat >"${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"${FAKE_LOG}"
if [ "$1" = login ]; then
  cat >"${FAKE_STDIN:-/dev/null}"
  [ "${FAKE_DOCKER_LOGIN_EXIT:-0}" -eq 0 ] || { echo "Error response from daemon: login attempt failed" >&2; exit 1; }
fi
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

# ---------------------------------------------------------------- ecr-public-login.sh

login() { # <aws mode> [docker login exit code]
  : >"${work}/log"
  : >"${work}/stdin"
  status=0
  env PATH="${work}/bin:${PATH}" FAKE_LOG="${work}/log" FAKE_AWS_MODE="$1" FAKE_STDIN="${work}/stdin" \
    FAKE_DOCKER_LOGIN_EXIT="${2:-0}" bash "$(pwd)/scripts/ecr-public-login.sh" >"${work}/out" 2>&1 || status=$?
}

login public_ok
if [ "${status}" -eq 0 ] \
  && grep -qx 'aws ecr-public get-login-password --region us-east-1' "${work}/log" \
  && grep -qx 'docker login --username AWS --password-stdin public.ecr.aws' "${work}/log" \
  && [ "$(cat "${work}/stdin")" = "public-secret-token" ]; then
  pass "login asks ECR Public (us-east-1) for a token and gives it to docker on stdin"
else fail "login should use aws ecr-public get-login-password and docker login --password-stdin"; fi

if ! grep -q 'public-secret-token' "${work}/out"; then pass "the token is never printed"; else fail "the token must not appear in the output"; fi

login public_denied
if [ "${status}" -eq 0 ] && grep -q '^::warning::' "${work}/out" && ! grep -q 'docker login' "${work}/log"; then
  pass "a token that cannot be fetched only warns, and docker is not asked to log in"
else fail "a denied token request must warn, exit 0 and skip docker login (status=${status})"; fi

login public_empty
if [ "${status}" -eq 0 ] && grep -q '^::warning::' "${work}/out" && ! grep -q 'docker login' "${work}/log"; then
  pass "an empty token is treated as no login"
else fail "an empty token must not be passed to docker"; fi

login public_ok 1
if [ "${status}" -eq 0 ] && grep -q '^::warning::docker login' "${work}/out" && ! grep -q 'public-secret-token' "${work}/out"; then
  pass "a docker login failure only warns, without printing the token"
else fail "a failing docker login must warn and exit 0"; fi

# ---------------------------------------------------------------- release tags (IMAGE_TAG, EXTRA_TAGS)

rel() { # <command> <FAKE_TAGS> [extra env assignments...]
  local command="$1" tags="$2"
  shift 2
  : >"${work}/log"
  : >"${work}/out"
  status=0
  env PATH="${work}/bin:${PATH}" FAKE_LOG="${work}/log" FAKE_AWS_MODE=found FAKE_TAGS="${tags}" \
    ECR_REPOSITORY=portfolio-api AWS_REGION=us-east-1 GIT_SHA="${sha}" GITHUB_OUTPUT="${work}/out" \
    IMAGE_TAG=v1.2.3 EXTRA_TAGS="sha-${sha}-v1.2.3" "$@" bash "${script}" "${command}" 2>"${work}/err" || status=$?
}

rel lookup "v1.2.3=${digest}"
if [ "${status}" -eq 0 ] && grep -qx 'found=true' "${work}/out" && grep -q -- '--image-ids imageTag=v1.2.3' "${work}/log"; then
  pass "a release is looked up by its version tag, not by the commit tag"
else fail "lookup should use IMAGE_TAG"; fi

rel lookup "sha-${sha}=${digest}"
if [ "${status}" -eq 0 ] && grep -qx 'found=false' "${work}/out"; then
  pass "an existing development image of the same commit does not count as the release"
else fail "the commit tag must not satisfy a release lookup"; fi

rel push "" ECR_REGISTRY=123456789012.dkr.ecr.us-east-1.amazonaws.com
pushes="$(grep -c '^docker push' "${work}/log" || true)"
if [ "${status}" -eq 0 ] && [ "${pushes}" -eq 1 ] && grep -qx "docker push --quiet 123456789012.dkr.ecr.us-east-1.amazonaws.com/portfolio-api:v1.2.3" "${work}/log"; then
  pass "push sends the image once, under the main tag only"
else fail "push should push only IMAGE_TAG (pushes=${pushes})"; fi

rel extra-tags "v1.2.3=${digest}"
if [ "${status}" -eq 0 ] && grep -q -- "put-image .*--image-tag sha-${sha}-v1.2.3 " "${work}/log"; then
  pass "the missing extra tag is added to the same image with its manifest"
else fail "extra-tags should put the missing tag"; fi

rel extra-tags "v1.2.3=${digest};sha-${sha}-v1.2.3=${digest}"
if [ "${status}" -eq 0 ] && ! grep -q 'put-image' "${work}/log"; then
  pass "extra tags that already point at the image are left alone (a repeated run is safe)"
else fail "an existing extra tag must not be put again"; fi

rel extra-tags "v1.2.3=${digest};sha-${sha}-v1.2.3=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
if [ "${status}" -ne 0 ] && grep -q 'already points at a different image' "${work}/err" && ! grep -q 'put-image' "${work}/log"; then
  pass "an extra tag that points at another image is an error, never overwritten"
else fail "a conflicting extra tag must fail"; fi

rel extra-tags "v1.2.3=${digest}" EXTRA_TAGS=
if [ "${status}" -eq 0 ] && ! grep -q 'put-image' "${work}/log"; then pass "no extra tags means nothing to do"; else fail "empty EXTRA_TAGS must be a no-op"; fi

rel extra-tags "unrelated=${digest}"
if [ "${status}" -ne 0 ]; then pass "extra tags cannot be added to an image that is not in ECR"; else fail "extra-tags needs the main image"; fi

rel lookup "" IMAGE_TAG="latest tag"
if [ "${status}" -ne 0 ]; then pass "an invalid tag name is rejected"; else fail "invalid tags must be rejected"; fi

# ---------------------------------------------------------------- image-commit.sh

commit_of() { # <aws mode> <digest>
  : >"${work}/log"
  : >"${work}/out"
  status=0
  env PATH="${work}/bin:${PATH}" FAKE_LOG="${work}/log" FAKE_AWS_MODE="$1" ECR_REPOSITORY=portfolio-api \
    AWS_REGION=us-east-1 GITHUB_OUTPUT="${work}/out" bash "$(pwd)/scripts/image-commit.sh" "$2" 2>"${work}/err" || status=$?
}

commit_of by_digest "${digest}"
if [ "${status}" -eq 0 ] && grep -qx 'commit=0123456789abcdef0123456789abcdef01234567' "${work}/out" \
  && grep -q -- "--image-ids imageDigest=${digest}" "${work}/log"; then
  pass "the commit is read from the sha-<commit> tag of the digest, ignoring other tags"
else fail "image-commit should return the commit from the sha- tag"; fi

if grep -qx 'version=0.0.0-dev' "${work}/out"; then pass "an image with only a commit tag is a development build (0.0.0-dev)"; else fail "a commit-only tag means version 0.0.0-dev"; fi

commit_of by_digest_release "${digest}"
if [ "${status}" -eq 0 ] && grep -qx 'commit=0123456789abcdef0123456789abcdef01234567' "${work}/out" && grep -qx 'version=1.2.3' "${work}/out"; then
  pass "a release image gives its commit and its version from the sha-<commit>-v<version> tag"
else fail "image-commit should read the version of a release image"; fi

commit_of by_digest_both "${digest}"
if [ "${status}" -eq 0 ] && grep -qx 'version=1.2.3' "${work}/out" && ! grep -q 'version=0.0.0-dev' "${work}/out"; then
  pass "the release tag wins over a plain commit tag"
else fail "a release tag must win"; fi

commit_of by_digest_untagged "${digest}"
if [ "${status}" -ne 0 ] && ! grep -q commit= "${work}/out" && grep -q 'no sha-<commit> tag' "${work}/err"; then
  pass "an image without a commit tag is refused"
else fail "an untagged image must be refused"; fi

commit_of by_digest_wrong_tags "${digest}"
if [ "${status}" -ne 0 ] && ! grep -q commit= "${work}/out"; then pass "tags that are not sha-<40 hex> are not taken for a commit"; else fail "a malformed sha- tag must not count"; fi

commit_of missing "${digest}"
if [ "${status}" -ne 0 ] && grep -q 'is not an image in portfolio-api' "${work}/err"; then pass "a digest that is not in the repository is refused"; else fail "an unknown digest must be refused"; fi

commit_of denied "${digest}"
if [ "${status}" -ne 0 ] && grep -q 'AccessDeniedException' "${work}/err"; then pass "an AWS error is shown, not hidden"; else fail "other errors must be reported"; fi

commit_of by_digest "latest"
if [ "${status}" -ne 0 ] && [ ! -s "${work}/log" ]; then pass "a malformed digest is rejected before any AWS call"; else fail "the digest must be validated first"; fi

if [ "${failures}" -ne 0 ]; then
  echo "${failures} test(s) failed" >&2
  exit 1
fi
echo "all ecr-image tests passed"
