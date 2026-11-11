#!/usr/bin/env bash
#
# Tear down the AKS cluster + ArgoCD stack and clean up local Terraform state.
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

  command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl is not installed or not on PATH." >&2
    exit 1
  }

  if ! az account show >/dev/null 2>&1; then
    echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2
    exit 1
  fi

}


function delete_kind_if_present() {

  local kind="$1"
  shift

  if ! kubectl get "$kind" "$@" --no-headers >/dev/null 2>&1; then
    return 0
  fi

  kubectl delete "$kind" --all "$@" --ignore-not-found --timeout=15m || true
}


function crossplane_predestroy_cleanup() {

  # Crossplane-managed Azure resources (the MySQL Flexible Servers, firewall
  # rules and databases) live only in the cluster's etcd, not in Terraform
  # state. If we let `terraform destroy` tear down the AKS cluster first,
  # Crossplane never gets a chance to delete those Azure resources and they are
  # orphaned (left running and billing in the resource group).

  if [ ! -f terraform.tfstate ] && [ ! -d .terraform ]; then
    echo "==> No Terraform state found; skipping Crossplane pre-destroy cleanup."
    return
  fi

  local rg_name cluster_name
  rg_name="$(terraform console <<<'var.resource_group_name' 2>/dev/null | tr -d '"' || true)"
  cluster_name="$(terraform console <<<'var.cluster_name' 2>/dev/null | tr -d '"' || true)"

  if [ -z "$rg_name" ] || [ -z "$cluster_name" ]; then
    echo "==> Could not read cluster details from Terraform; skipping Crossplane pre-destroy cleanup."
    return
  fi

  if ! az aks get-credentials \
        --resource-group "$rg_name" \
        --name "$cluster_name" \
        --overwrite-existing >/dev/null 2>&1; then
    echo "==> AKS cluster '${cluster_name}' not reachable; skipping Crossplane pre-destroy cleanup."
    return
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "==> Cluster API not reachable; skipping Crossplane pre-destroy cleanup."
    return
  fi

  echo "==> Deleting ArgoCD Applications that manage Crossplane resources"
  kubectl -n argocd delete application portable-database crossplane-managed-resource \
    --cascade=foreground --ignore-not-found --timeout=15m || true

  echo "==> Deleting Crossplane composite/managed MySQL resources directly (belt and suspenders)"
  delete_kind_if_present mysql2 --all-namespaces
  delete_kind_if_present flexibleserver.dbformysql.azure.upbound.io
  delete_kind_if_present flexibledatabase.dbformysql.azure.upbound.io
  delete_kind_if_present flexibleserverfirewallrule.dbformysql.azure.upbound.io

  echo "==> Waiting for all Crossplane-managed Azure MySQL resources to be fully deleted"
  wait_for_crossplane_mysql_gone

  echo "==> Deleting Crossplane Azure ProviderConfigs before Terraform tears them down"
  delete_crossplane_providerconfigs

}


function delete_crossplane_providerconfigs() {

  # Crossplane holds an "in-use.crossplane.io" finalizer on a ProviderConfig
  # until every managed resource referencing it is gone. By this point the MySQL
  # resources are deleted, so the finalizer should clear quickly. We delete the
  # ProviderConfigs here (with a bounded wait) so that Terraform's own delete of
  # kubernetes_manifest.crossplane_azure_providerconfig - which has no timeout
  # and would otherwise block indefinitely on a stuck finalizer - finds them
  # already gone and returns immediately.

  local pc_kinds=(
    "providerconfig.azure.upbound.io"
    "clusterproviderconfig.azure.m.upbound.io"
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
      echo "    All Crossplane Azure ProviderConfigs are gone."
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


function wait_for_crossplane_mysql_gone() {

  local deadline=$(( $(date +%s) + 1200 )) # up to 20 minutes
  local remaining

  while true; do
    remaining=0
    for kind in \
      mysql2 \
      flexibleserver.dbformysql.azure.upbound.io \
      flexibledatabase.dbformysql.azure.upbound.io \
      flexibleserverfirewallrule.dbformysql.azure.upbound.io \
      flexibleserver.dbformysql.azure.m.upbound.io \
      flexibledatabase.dbformysql.azure.m.upbound.io \
      flexibleserverfirewallrule.dbformysql.azure.m.upbound.io; do
      # Skip kinds whose CRD is not (or no longer) installed. ArgoCD's cascade
      # can remove the XRD/provider CRDs before we poll, so `kubectl get` would
      # otherwise fail and - under `set -o pipefail`/`set -e` - kill the script.
      kubectl get "$kind" --all-namespaces --no-headers >/dev/null 2>&1 || continue
      local count
      count="$(kubectl get "$kind" --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d '[:space:]' || true)"
      remaining=$(( remaining + ${count:-0} ))
    done

    if [ "$remaining" -eq 0 ]; then
      echo "    All Crossplane-managed MySQL resources are gone."
      return
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "WARNING: Timed out waiting for Crossplane MySQL resources to delete." >&2
      echo "         ${remaining} resource(s) still present; the subsequent" >&2
      echo "         resource-group delete should clean up any leftover Azure" >&2
      echo "         servers, but verify in the Azure portal." >&2
      return
    fi

    echo "    ${remaining} resource(s) still deleting; waiting 15s..."
    sleep 15
  done

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
crossplane_predestroy_cleanup
terraform_destroy
cleanup_terraform_files_and_directories

echo "==> Cleanup complete."
