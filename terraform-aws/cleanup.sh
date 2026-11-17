#!/usr/bin/env bash
#
# Tear down the EKS cluster + ArgoCD stack and clean up local Terraform state.
#
# Usage:
#   ./cleanup.sh [aws-profile]
#
# The AWS profile defaults to "xforce-sandbox1". Pass a profile name as the
# first argument to use a different one.

DEFAULT_AWS_PROFILE="xforce-sandbox1"

function select_aws_profile() {

  # Exporting AWS_PROFILE makes the AWS CLI, the Terraform AWS provider and the
  # 'aws eks get-token' exec plugin (kubernetes/helm providers) use this profile.
  export AWS_PROFILE="${1:-$DEFAULT_AWS_PROFILE}"
  export TF_VAR_aws_profile="${AWS_PROFILE}"
  # Static credentials in the environment take precedence over AWS_PROFILE and
  # would silently bypass the profile (for example expired keys).
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  echo "Using AWS profile: ${AWS_PROFILE}"

}


function run_in_script_dir() {

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$SCRIPT_DIR"

}


function prerequisite_checks() {

  command -v terraform >/dev/null 2>&1 || {
    echo "ERROR: terraform is not installed or not on PATH." >&2
    exit 1
  }

  command -v aws >/dev/null 2>&1 || {
    echo "ERROR: AWS CLI (aws) is not installed or not on PATH." >&2
    exit 1
  }

  command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl is not installed or not on PATH." >&2
    exit 1
  }

  if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
    echo "ERROR: Not logged in to AWS with profile '${AWS_PROFILE}'. Run 'aws sso login --profile ${AWS_PROFILE}' first." >&2
    exit 1
  fi

}


function count_crossplane_managed_resources() {

  # "managed" is the Crossplane category that groups all managed resources of
  # every installed provider. If the CRDs are already gone, the count is 0.
  local count
  count="$(kubectl get managed --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
  echo "${count:-0}"

}


function crossplane_predestroy_cleanup() {

  # Crossplane-managed AWS resources (for example RDS instances) live only in
  # the cluster's etcd, not in Terraform state. If we let `terraform destroy`
  # tear down the EKS cluster first, Crossplane never gets a chance to delete
  # those AWS resources and they are orphaned (left running and billing, and
  # they can block deletion of the VPC).

  if [ ! -f terraform.tfstate ] && [ ! -d .terraform ]; then
    echo "==> No Terraform state found; skipping Crossplane pre-destroy cleanup."
    return
  fi

  local region cluster_name
  region="$(terraform console <<<'var.region' 2>/dev/null | tr -d '"' || true)"
  cluster_name="$(terraform console <<<'var.cluster_name' 2>/dev/null | tr -d '"' || true)"

  if [ -z "$region" ] || [ -z "$cluster_name" ]; then
    echo "==> Could not read cluster details from Terraform; skipping Crossplane pre-destroy cleanup."
    return
  fi

  if ! aws eks update-kubeconfig \
        --region "$region" \
        --name "$cluster_name" \
        --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
    echo "==> EKS cluster '${cluster_name}' not reachable; skipping Crossplane pre-destroy cleanup."
    return
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "==> Cluster API not reachable; skipping Crossplane pre-destroy cleanup."
    return
  fi

  echo "==> Deleting ArgoCD Applications that manage Crossplane resources"
  kubectl -n argocd delete application portable-app crossplane-managed-resource \
    --cascade=foreground --ignore-not-found --timeout=15m || true

  echo "==> Deleting remaining Crossplane managed resources directly (belt and suspenders)"
  kubectl delete managed --all --all-namespaces --ignore-not-found --wait=false >/dev/null 2>&1 || true

  echo "==> Waiting for all Crossplane-managed AWS resources to be fully deleted"
  wait_for_crossplane_managed_gone

  echo "==> Deleting Crossplane AWS ProviderConfigs before Terraform tears them down"
  delete_crossplane_providerconfigs

}


function delete_crossplane_providerconfigs() {

  # Crossplane holds an "in-use.crossplane.io" finalizer on a ProviderConfig
  # until every managed resource referencing it is gone. By this point the
  # managed resources are deleted, so the finalizer should clear quickly. We
  # delete the ProviderConfigs here (with a bounded wait) so that Terraform's
  # own delete of kubernetes_manifest.crossplane_aws_providerconfig - which has
  # no timeout and would otherwise block indefinitely on a stuck finalizer -
  # finds them already gone and returns immediately.

  local pc_kinds=(
    "providerconfig.aws.upbound.io"
    "clusterproviderconfig.aws.m.upbound.io"
  )

  local kind
  for kind in "${pc_kinds[@]}"; do
    if ! kubectl get "$kind" >/dev/null 2>&1; then
      continue
    fi
    kubectl delete "$kind" --all --ignore-not-found --timeout=5m || true
  done

  local deadline=$(( $(date +%s) + 300 ))
  while true; do
    local remaining=0 name
    for kind in "${pc_kinds[@]}"; do
      kubectl get "$kind" >/dev/null 2>&1 || continue
      local n
      n="$(kubectl get "$kind" --no-headers 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
      remaining=$(( remaining + ${n:-0} ))
    done

    if [ "$remaining" -eq 0 ]; then
      echo "    All Crossplane AWS ProviderConfigs are gone."
      return
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "    ProviderConfig(s) still present after wait; stripping in-use finalizers."
      for kind in "${pc_kinds[@]}"; do
        kubectl get "$kind" >/dev/null 2>&1 || continue
        for name in $(kubectl get "$kind" -o name 2>/dev/null); do
          kubectl patch "$name" --type=merge -p '{"metadata":{"finalizers":null}}' || true
        done
      done
      return
    fi

    echo "    ProviderConfig(s) still deleting; waiting 10s..."
    sleep 10
  done

}


function wait_for_crossplane_managed_gone() {

  local deadline=$(( $(date +%s) + 1200 )) # up to 20 minutes
  local remaining

  while true; do
    remaining="$(count_crossplane_managed_resources)"

    if [ "$remaining" -eq 0 ]; then
      echo "    All Crossplane-managed AWS resources are gone."
      return
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "WARNING: Timed out waiting for Crossplane managed resources to delete." >&2
      echo "         ${remaining} resource(s) still present; they may be left" >&2
      echo "         behind in AWS and block the VPC delete. Verify in the AWS console." >&2
      return
    fi

    echo "    ${remaining} resource(s) still deleting; waiting 15s..."
    sleep 15
  done

}


function terraform_destroy_state_resources_only() {

  local addr
  local targets=()

  # Skip data sources; only managed resources can be destroyed.
  while IFS= read -r addr; do
    case "$addr" in
      data.* | *.data.*) continue ;;
      "") continue ;;
    esac
    targets+=("-target=${addr}")
  done < <(terraform state list)

  if [ "${#targets[@]}" -eq 0 ]; then
    echo "    No managed resources in the state; nothing to destroy."
    return
  fi

  terraform destroy -input=false -auto-approve "${targets[@]}"

}


function terraform_destroy() {

  if [ -f terraform.tfstate ] || [ -d .terraform ]; then
    echo "==> terraform destroy"
    if ! terraform destroy -input=false -auto-approve; then
      # A previous apply that stopped early (for example a node group that
      # never became ACTIVE) leaves kubernetes_manifest resources out of the
      # state. Terraform still cannot plan them because their CRDs were never
      # installed. Destroy only what is actually in the state instead.
      echo "==> Full destroy failed; retrying with only the resources in the state"
      terraform_destroy_state_resources_only
    fi
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

select_aws_profile "$@"
run_in_script_dir
prerequisite_checks
crossplane_predestroy_cleanup
terraform_destroy
cleanup_terraform_files_and_directories

echo "==> Cleanup complete."
