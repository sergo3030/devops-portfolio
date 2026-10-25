#!/usr/bin/env bash
# Shared by the teardown scripts (teardown-api.sh, teardown-aws.sh, up-prod.sh). Source it.
# shellcheck shell=bash

# shellcheck disable=SC2034 # used by the scripts that source this file
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-portfolio-bootstrap}"
export AWS_REGION="${AWS_REGION:-us-east-1}"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
heading() { printf '\n=== %s ===\n' "$*"; }

# The scripts act as the bootstrap admin (IAM user portfolio-admin, `aws login`), never as root and
# never with stored keys. Nothing is printed of the account ID.
require_admin_session() {
  local arn
  arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" ||
    die "no AWS session. Run: aws login --profile ${AWS_PROFILE}"
  [[ "${arn}" == *":user/portfolio-admin" ]] ||
    die "signed in as ${arn##*:}, expected user/portfolio-admin (not root)"
}

# A destructive step needs a person at a keyboard. TEARDOWN_ALLOW_PIPE exists for the tests only.
require_terminal() {
  if [ -t 0 ] || [ "${TEARDOWN_ALLOW_PIPE:-}" = "1" ]; then return 0; fi
  die "apply mode asks for confirmation and needs a terminal. Run it yourself, not from a pipe."
}

confirm_phrase() { # <phrase>
  local answer
  printf 'Type "%s" to continue: ' "$1" >&2
  IFS= read -r answer || answer=""
  [ "${answer}" = "$1" ] || die "not confirmed. Nothing more was changed."
}

ask_yes() { # <question>
  local answer
  printf '%s [y/N] ' "$1" >&2
  IFS= read -r answer || answer=""
  [ "${answer}" = "y" ] || die "not confirmed. Nothing more was changed."
}

# Plan, show the whole rendered plan, keep the saved plan file for the apply.
plan_and_show() { # <root> <plan-file> <tofu plan arguments...>
  local root="$1" file="$2"
  shift 2
  tofu -chdir="${root}" plan -input=false -no-color -out="${file}" "$@" >/dev/null
  tofu -chdir="${root}" show -no-color "${file}"
}
