#!/usr/bin/env bash
#
# Tear down the AKS cluster + ArgoCD stack and clean up local Terraform state.
#
# Prerequisites:
#   - terraform >= 1.9
#   - Azure CLI, logged in via `az login`
#
# Usage:
#   ./cleanup.sh

function run_in_script_dir() {

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR"

}


function prerequisite_checks() {

  command -v terraform >/dev/null 2>&1 || {
    echo "ERROR: terraform is not installed or not on PATH." >&2
    exit 1
  }

  command -v az >/dev/null 2>&1 || {
    echo "ERROR: Azure CLI (az) is not installed or not on PATH." >&2
    exit 1
  }

  if ! az account show >/dev/null 2>&1; then
    echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2
    exit 1
  fi

}


function terraform_destroy() {

  if [ -f terraform.tfstate ] || [ -d .terraform ]; then
    echo "==> terraform destroy"
    terraform destroy -input=false -auto-approve
  else
    echo "==> No Terraform state found; nothing to destroy."
  fi

}


function cleanup_terraform_files_and_directories() {
  echo "==> Removing local Terraform working files"

  rm -rf .terraform
  rm -f .terraform.lock.hcl
  rm -f terraform.tfstate terraform.tfstate.backup
  rm -f tfplan
}

# Main

set -euo pipefail

run_in_script_dir
prerequisite_checks
terraform_destroy
cleanup_terraform_files_and_directories

echo "==> Cleanup complete."
