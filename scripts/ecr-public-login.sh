#!/usr/bin/env bash
# Logs Docker in to public ECR with the AWS credentials the job already has (assumed through
# GitHub OIDC), so that image pulls from public.ecr.aws count against this AWS account and not
# against the shared anonymous limit of the GitHub runners, which answers "429 Too Many
# Requests" (decisions.md D40).
#
#   ecr-public-login.sh
#
# It never fails the job. If the login does not work (no permission, AWS unreachable), pulls just
# stay anonymous, which is how the build worked before, and a warning says so. The token is passed
# to Docker on stdin and is never printed.
set -uo pipefail

warn() { echo "::warning::$*"; }

err="$(mktemp)"
trap 'rm -f "${err}"' EXIT

# ECR Public answers only in us-east-1, whatever region the job uses for other things.
if ! password="$(aws ecr-public get-login-password --region us-east-1 2>"${err}")" || [ -z "${password}" ]; then
  warn "Could not get a public ECR login token, so image pulls stay anonymous (they may be rate limited): $(head -c 300 "${err}" | tr '\n' ' ')"
  exit 0
fi

if ! printf '%s' "${password}" | docker login --username AWS --password-stdin public.ecr.aws >/dev/null 2>"${err}"; then
  warn "docker login to public.ecr.aws failed, so image pulls stay anonymous: $(head -c 300 "${err}" | tr '\n' ' ')"
  exit 0
fi

echo "Logged in to public.ecr.aws with the project's AWS identity"
