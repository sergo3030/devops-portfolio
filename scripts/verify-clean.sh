#!/usr/bin/env bash
# Read-only check of what the project has left in the AWS account.
#
#   verify-clean.sh [level1|level2]
#
#   level1  after `just teardown-api`: only the bootstrap root may remain (state bucket, OIDC
#           provider, the plan, ecr-push and apply roles, the permission boundary, the Budgets and
#           the anomaly monitor)
#   level2  after `just teardown-aws` (the default): nothing may remain
#
# It lists, by the `portfolio-` name prefix: Lambda functions, ECR repositories, DynamoDB tables,
# S3 buckets, CloudWatch log groups, IAM roles and policies, the GitHub OIDC provider and Budgets,
# and it searches the resources tagged Project=portfolio (the tagging API does not list IAM roles,
# which is why the roles are also listed by name). Anything not allowed at the level is printed and
# the exit status is 1. A failing AWS call fails the check: it never reports "clean" on an error.
#
# Region us-east-1 only. The permission boundary denies other regions, so nothing can be there.
# VERIFY_CLEAN_INPUT=<file> reads "<category><TAB><name>" lines instead of calling AWS (tests).
set -euo pipefail
shopt -s inherit_errexit # a failing AWS call inside gather must stop the check

level="${1:-level2}"
case "${level}" in level1 | level2) ;; *)
  echo "usage: verify-clean.sh [level1|level2]" >&2
  exit 2
  ;;
esac

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""
export MSYS_NO_PATHCONV=1 # Git Bash would turn /aws/lambda/... into a Windows path

list() { # <category>: names on stdin (text output), one per line out
  tr '\t' '\n' | sed '/^$/d;/^None$/d' | sed "s/^/$1\t/"
}

gather() {
  if [ -n "${VERIFY_CLEAN_INPUT:-}" ]; then
    cat "${VERIFY_CLEAN_INPUT}"
    return 0
  fi
  local account
  account="$(aws sts get-caller-identity --query Account --output text)"
  aws lambda list-functions --query "Functions[?starts_with(FunctionName,'portfolio-')].FunctionName" --output text | list lambda
  aws ecr describe-repositories --query "repositories[?starts_with(repositoryName,'portfolio-')].repositoryName" --output text | list ecr
  aws dynamodb list-tables --query "TableNames[?starts_with(@,'portfolio-')]" --output text | list dynamodb
  aws s3api list-buckets --query "Buckets[?starts_with(Name,'portfolio-')].Name" --output text | list s3
  aws logs describe-log-groups --log-group-name-prefix /aws/lambda/portfolio- --query "logGroups[].logGroupName" --output text | list log-group
  aws iam list-roles --query "Roles[?starts_with(RoleName,'portfolio-')].RoleName" --output text | list iam-role
  aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName,'portfolio-')].PolicyName" --output text | list iam-policy
  aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[].Arn" --output text |
    tr '\t' '\n' | { grep 'token.actions.githubusercontent.com' || true; } | sed 's#.*oidc-provider/##' | list oidc
  aws budgets describe-budgets --account-id "${account}" --query "Budgets[?starts_with(BudgetName,'portfolio-')].BudgetName" --output text | list budget
  aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=portfolio --query "ResourceTagMappingList[].ResourceARN" --output text | list tagged
}

# What the bootstrap root owns, and so may exist after Level 1.
bootstrap_owns() { # <category> <name>
  case "$1:$2" in
    s3:portfolio-tfstate-* | \
      iam-role:portfolio-plan | iam-role:portfolio-ecr-push | iam-role:portfolio-apply | \
      iam-policy:portfolio-boundary | \
      oidc:token.actions.githubusercontent.com | \
      budget:portfolio-monthly-* | budget:portfolio-alert-test | \
      tagged:arn:aws:s3:::portfolio-tfstate-* | \
      tagged:arn:aws:iam::*:role/portfolio-plan | tagged:arn:aws:iam::*:role/portfolio-ecr-push | \
      tagged:arn:aws:iam::*:role/portfolio-apply | tagged:arn:aws:iam::*:policy/portfolio-boundary | \
      tagged:arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com | \
      tagged:arn:aws:budgets::*:budget/portfolio-* | \
      tagged:arn:aws:ce::*:anomalymonitor/* | tagged:arn:aws:ce::*:anomalysubscription/*)
      return 0
      ;;
  esac
  return 1
}

found="$(gather)"
unexpected=""
allowed_count=0
while IFS=$'\t' read -r category name; do
  [ -n "${category}" ] || continue
  if [ "${level}" = level1 ] && bootstrap_owns "${category}" "${name}"; then
    allowed_count=$((allowed_count + 1))
  else
    unexpected+="  ${category}: ${name}"$'\n'
  fi
done <<<"${found}"

if [ -n "${unexpected}" ]; then
  echo "NOT CLEAN at ${level}. Left behind:" >&2
  printf '%s' "${unexpected}" >&2
  exit 1
fi
if [ "${level}" = level1 ]; then
  echo "clean at level1: only the bootstrap root remains (${allowed_count} items)"
else
  echo "clean at level2: nothing tagged or named portfolio-* remains"
fi
