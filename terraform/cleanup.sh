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

  command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl is not installed or not on PATH." >&2
    exit 1
  }

  if ! az account show >/dev/null 2>&1; then
    echo "ERROR: Not logged in to Azure. Run 'az login' first." >&2
    exit 1
  fi

}


function crossplane_predestroy_cleanup() {

  # Crossplane-managed Azure resources (the MySQL Flexible Servers, firewall
  # rules and databases) live only in the cluster's etcd, not in Terraform
  # state. If we let `terraform destroy` tear down the AKS cluster first,
  # Crossplane never gets a chance to delete those Azure resources and they are
  # orphaned (left running and billing in the resource group).
  #
  # So before touching Terraform we:
  #   1. delete the ArgoCD Applications that manage Crossplane resources (their
  #      resources-finalizer cascades the delete to the managed resources), and
  #   2. delete the Crossplane composite/managed resources directly, and
  #   3. wait for them to be fully gone (i.e. Crossplane confirmed Azure
  #      actually deleted the servers) before returning.

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

  # Grab kubeconfig for the cluster. If the cluster is already gone there is
  # nothing to clean up in-cluster.
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
  # --cascade=foreground + the resources-finalizer makes ArgoCD prune the
  # resources it deployed. Ignore errors if an Application is already gone.
  kubectl -n argocd delete application portable-database crossplane-managed-resource \
    --cascade=foreground --ignore-not-found --timeout=15m || true

  echo "==> Deleting Crossplane composite/managed MySQL resources directly (belt and suspenders)"
  # In case ArgoCD is not configured to prune, delete the Crossplane resources
  # ourselves. --ignore-not-found keeps this idempotent.
  kubectl delete mysql2 --all --all-namespaces --ignore-not-found --timeout=15m || true
  kubectl delete flexibleserver.dbformysql.azure.upbound.io --all --ignore-not-found --timeout=15m || true
  kubectl delete flexibledatabase.dbformysql.azure.upbound.io --all --ignore-not-found --timeout=15m || true
  kubectl delete flexibleserverfirewallrule.dbformysql.azure.upbound.io --all --ignore-not-found --timeout=15m || true

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
  #
  # As a last resort, if a finalizer is still stuck after the wait, we strip it
  # so the destroy cannot hang forever. This is safe because the external Azure
  # resources have already been confirmed deleted above.

  # Both the cluster-scoped azure.upbound.io ProviderConfig (used by the raw
  # managed resources) and the azure.m.upbound.io ClusterProviderConfig (used by
  # the portable-database composition) can carry the finalizer.
  local pc_kinds=(
    "providerconfig.azure.upbound.io"
    "clusterproviderconfig.azure.m.upbound.io"
  )

  local kind
  for kind in "${pc_kinds[@]}"; do
    if ! kubectl get "$kind" >/dev/null 2>&1; then
      # CRD not installed (provider variant not present); skip quietly.
      continue
    fi
    kubectl delete "$kind" --all --ignore-not-found --timeout=5m || true
  done

  # Bounded wait for them to disappear; strip finalizers if still stuck.
  local deadline=$(( $(date +%s) + 300 )) # up to 5 minutes
  while true; do
    local remaining=0 name
    for kind in "${pc_kinds[@]}"; do
      kubectl get "$kind" >/dev/null 2>&1 || continue
      local n
      n="$(kubectl get "$kind" --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
      remaining=$(( remaining + n ))
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
          # Safe: the external Azure resources are already confirmed deleted.
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

  # Poll until no MySQL-related managed resources remain in the cluster.
  # Crossplane only removes a resource's finalizer once Azure has confirmed the
  # underlying server/database is actually deleted, so "gone from the cluster"
  # means "gone from Azure".

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
      local count
      count="$(kubectl get "$kind" --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')"
      remaining=$(( remaining + count ))
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
