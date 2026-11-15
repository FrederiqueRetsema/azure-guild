#!/usr/bin/env bash
#
# Show the IP addresses of the VMs deployed by the portable app in AWS and
# Azure. The VMs are looked up directly in the clouds, so no Kubernetes
# context is needed.
#
#   AWS:   EC2 instances with tag Name=guild-vm in eu-west-1.
#   Azure: VMs in resource group frederique-azure-guild.
#
# Usage:
#   ./show-vm-ips.sh [aws-profile]
#
# The AWS profile defaults to "xforce-sandbox1". The Azure part uses the
# current 'az login' session and subscription. A cloud that is not logged in
# is skipped with a warning.

DEFAULT_AWS_PROFILE="xforce-sandbox1"
AWS_REGION="eu-west-1"
AWS_VM_NAME="guild-vm"
AZURE_RESOURCE_GROUP="frederique-azure-guild"


function show_aws_vms() {

  echo "==> AWS (profile ${AWS_PROFILE}, region ${AWS_REGION})"

  if ! command -v aws >/dev/null 2>&1; then
    echo "    WARNING: AWS CLI (aws) is not installed; skipping AWS." >&2
    return
  fi

  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "    WARNING: Not logged in to AWS profile '${AWS_PROFILE}'. Run 'aws sso login --profile ${AWS_PROFILE}'; skipping AWS." >&2
    return
  fi

  local result
  result="$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters \
      "Name=tag:Name,Values=${AWS_VM_NAME}" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value, InstanceId, State.Name, PublicIpAddress || `-`, PrivateIpAddress || `-`]' \
    --output text)"

  if [ -z "$result" ]; then
    echo "    No VMs found."
    return
  fi

  {
    printf 'NAME\tINSTANCE\tSTATE\tPUBLIC IP\tPRIVATE IP\n'
    echo "$result"
  } | column -t -s $'\t' | sed 's/^/    /'

}


function show_azure_vms() {

  echo "==> Azure (resource group ${AZURE_RESOURCE_GROUP})"

  if ! command -v az >/dev/null 2>&1; then
    echo "    WARNING: Azure CLI (az) is not installed; skipping Azure." >&2
    return
  fi

  if ! az account show >/dev/null 2>&1; then
    echo "    WARNING: Not logged in to Azure. Run 'az login'; skipping Azure." >&2
    return
  fi

  local result
  result="$(az vm list-ip-addresses \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query '[].[virtualMachine.name, virtualMachine.network.publicIpAddresses[0].ipAddress || `-`, virtualMachine.network.privateIpAddresses[0] || `-`]' \
    --output tsv 2>&1)" || {
    echo "    WARNING: Could not list VMs: ${result}" >&2
    return
  }

  if [ -z "$result" ]; then
    echo "    No VMs found."
    return
  fi

  {
    printf 'NAME\tPUBLIC IP\tPRIVATE IP\n'
    echo "$result"
  } | column -t -s $'\t' | sed 's/^/    /'

}


# Main

set -uo pipefail

export AWS_PROFILE="${1:-$DEFAULT_AWS_PROFILE}"

show_aws_vms
echo
show_azure_vms
