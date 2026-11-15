#!/usr/bin/env bash
#
# Update the pinned AlmaLinux AMI ID in aws/composition-virtualmachine.yaml.
# AlmaLinux does not publish a Systems Manager public parameter, so the latest
# AMI is looked up with EC2 DescribeImages (owner: AlmaLinux OS Foundation).
#
# Only eu-west-1 is handled. Requires a logged-in session for the AWS profile.
#
# Usage:
#   ./update-aws-amis.sh [--dry-run] [aws-profile]
#
# The AWS profile defaults to "xforce-sandbox1". --dry-run only shows what
# would change.

DEFAULT_AWS_PROFILE="xforce-sandbox1"
REGION="eu-west-1"
ALMALINUX_OWNER_ID="764336703387"
ALMALINUX_MAJOR="10"

function run_in_script_dir() {

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR"
  COMPOSITION="aws/composition-virtualmachine.yaml"

}


function prerequisite_checks() {

  command -v aws >/dev/null 2>&1 || {
    echo "ERROR: AWS CLI (aws) is not installed or not on PATH." >&2
    exit 1
  }

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "ERROR: Not logged in to AWS profile '${AWS_PROFILE}'. Run 'aws sso login --profile ${AWS_PROFILE}' first." >&2
    exit 1
  fi

  if [ ! -f "$COMPOSITION" ]; then
    echo "ERROR: ${COMPOSITION} not found." >&2
    exit 1
  fi

}


function find_latest_ami() {

  echo "==> Looking up the latest AlmaLinux ${ALMALINUX_MAJOR} x86_64 AMI in ${REGION}"

  local result
  result="$(aws ec2 describe-images \
    --region "$REGION" \
    --owners "$ALMALINUX_OWNER_ID" \
    --filters \
      "Name=name,Values=AlmaLinux OS ${ALMALINUX_MAJOR}.*" \
      "Name=architecture,Values=x86_64" \
      "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].[ImageId, Name]' \
    --output text)"

  AMI_ID="$(echo "$result" | awk '{print $1}')"
  AMI_NAME="$(echo "$result" | cut -f2-)"

  if ! echo "$AMI_ID" | grep -Eq '^ami-[0-9a-f]+$'; then
    echo "ERROR: No AlmaLinux ${ALMALINUX_MAJOR} AMI found (got: '${result}')." >&2
    exit 1
  fi

  # Version for the comment, for example "10.2" from "AlmaLinux OS 10.2.20261109.0 x86_64".
  AMI_VERSION="$(echo "$AMI_NAME" | grep -Eo '[0-9]+\.[0-9]+' | head -n 1)"
  AMI_VERSION="${AMI_VERSION:-$ALMALINUX_MAJOR}"

  echo "    Found ${AMI_ID} (${AMI_NAME})"

}


function update_composition() {

  local current
  current="$(grep -Eo "\"${REGION}\" \"ami-[0-9a-f]+\"" "$COMPOSITION" | grep -Eo 'ami-[0-9a-f]+' || true)"

  if [ -z "$current" ]; then
    echo "ERROR: Could not find the ${REGION} AMI in ${COMPOSITION}." >&2
    exit 1
  fi

  if [ "$current" = "$AMI_ID" ]; then
    echo "==> ${COMPOSITION} already uses ${AMI_ID}; nothing to do."
    return
  fi

  echo "==> ${REGION}: ${current} -> ${AMI_ID}"

  if [ "$DRY_RUN" = "true" ]; then
    echo "    Dry run: ${COMPOSITION} not changed."
    return
  fi

  sed -i \
    -e "s|\"${REGION}\" \"ami-[0-9a-f]*\"|\"${REGION}\" \"${AMI_ID}\"|" \
    -e "s|AlmaLinux OS [0-9.]* (x86_64) community AMI|AlmaLinux OS ${AMI_VERSION} (x86_64) community AMI|" \
    "$COMPOSITION"

  echo "    ${COMPOSITION} updated. Review and commit the change."

}


# Main

set -euo pipefail

DRY_RUN="false"
PROFILE_ARG=""
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ]; then
    DRY_RUN="true"
  else
    PROFILE_ARG="$arg"
  fi
done

export AWS_PROFILE="${PROFILE_ARG:-$DEFAULT_AWS_PROFILE}"
echo "Using AWS profile: ${AWS_PROFILE}"

run_in_script_dir
prerequisite_checks
find_latest_ami
update_composition
