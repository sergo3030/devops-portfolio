#!/usr/bin/env bash
# Runs a command again when it fails, for steps that depend on a registry that sometimes
# answers "429 Too Many Requests" to the shared GitHub runners (public.ecr.aws, ghcr.io).
#
#   retry.sh <attempts> <seconds-between-attempts> -- <command> [args...]
#
# Exits 0 as soon as the command succeeds. After the last failed attempt it exits with the
# command's own exit code, so a real failure still fails the job. It retries every failure,
# so use it only for commands that are safe to run twice (a build, a download).
set -uo pipefail

usage() { echo "usage: retry.sh <attempts> <seconds> -- <command> [args...]" >&2; exit 2; }

[ "$#" -ge 4 ] || usage
attempts="$1"
pause="$2"
[ "$3" = "--" ] || usage
shift 3

[[ "${attempts}" =~ ^[1-9][0-9]*$ ]] || usage
[[ "${pause}" =~ ^[0-9]+$ ]] || usage

status=0
for attempt in $(seq 1 "${attempts}"); do
  "$@" && exit 0
  status=$?
  echo "retry.sh: attempt ${attempt}/${attempts} failed with exit code ${status}: $*" >&2
  [ "${attempt}" -lt "${attempts}" ] && sleep "${pause}"
done
exit "${status}"
