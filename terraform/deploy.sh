#!/usr/bin/env bash
#
# Deploy the AKS cluster + ArgoCD stack.
#
# Prerequisites:
#   - terraform >= 1.9
#   - Azure CLI, logged in via `az login`
#   - an active subscription selected (az account set --subscription <id>)
#
# Usage:
#   ./deploy.sh
#
# You must provide github_repo_url, either via a terraform.tfvars file or
# the TF_VAR_github_repo_url environment variable.

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

  if [ ! -f terraform.tfvars ] && [ -z "${TF_VAR_github_repo_url:-}" ]; then
    echo "ERROR: github_repo_url is not set." >&2
    echo "       Create terraform.tfvars (see terraform.tfvars.example)" >&2
    echo "       or export TF_VAR_github_repo_url=<url>." >&2
    exit 1
  fi

  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is not installed or not on PATH (needed to detect the public IP)." >&2
    exit 1
  }

  SUBSCRIPTION_NAME="$(az account show --query name -o tsv)"
  echo "Using Azure subscription: ${SUBSCRIPTION_NAME}"

}


function determine_public_ip() {

  echo "==> Determining the public IP address of this machine"

  # Try a few well-known endpoints so we are not dependent on a single service.
  local ip=""
  for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://checkip.amazonaws.com"; do
    ip="$(curl -fsS --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$ip" ]; then
      break
    fi
  done

  if [ -z "$ip" ]; then
    echo "ERROR: Could not determine the public IP address of this machine." >&2
    exit 1
  fi

  # Basic sanity check that this looks like an IPv4 address.
  if ! echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    echo "ERROR: Detected value '${ip}' does not look like a valid IPv4 address." >&2
    exit 1
  fi

  # Export as /32 so only this machine is allowed to reach the NodePort.
  export TF_VAR_nodeport_source_address_prefix="${ip}/32"
  echo "Public IP detected: ${ip}"
  echo "Restricting NodePort source address prefix to: ${TF_VAR_nodeport_source_address_prefix}"

}

function terraform_init() {

  echo "==> terraform init"
  terraform init -input=false

  echo "==> terraform validate"
  terraform validate

}


function terraform_deploy_k8s_cluster() {

  echo "==> Phase 1: cluster, ArgoCD and Crossplane Helm releases (bootstrap)"
  terraform apply -input=false -auto-approve \
    -target=azurerm_resource_group.this \
    -target=azurerm_kubernetes_cluster.this \
    -target=helm_release.argocd \
    -target=helm_release.crossplane

}


function terraform_deploy_crossplane_azure_family_provider() {

  echo "==> Phase 2: Crossplane Azure family provider"
  terraform apply -input=false -auto-approve \
    -target=kubernetes_manifest.crossplane_provider_family_azure

  RG_NAME="$(terraform console <<<'var.resource_group_name' | tr -d '"')"
  CLUSTER_NAME="$(terraform console <<<'var.cluster_name' | tr -d '"')"
  az aks get-credentials \
    --resource-group "$RG_NAME" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing >/dev/null

  echo "==> Waiting for provider-family-azure to become healthy"
  kubectl wait --for=condition=Healthy provider.pkg.crossplane.io/provider-family-azure \
               --timeout=600s

}


function terraform_deploy_rest() {

  echo "==> Phase 3: Apply the rest"
  terraform apply -input=false -auto-approve

}


function show_result() {

  ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  NODE_IP_ADDRESS=$(kubectl get nodes -o jsonpath="{range .items[*]}{.status.addresses[?(@.type=='ExternalIP')].address}{'\\n'}{end}" | head -n 1)  

  echo "ArgoCD"
  echo "======"
  echo "URL: https://${NODE_IP_ADDRESS}:30081"
  echo "User-id = admin, password = ${ARGOCD_PASSWORD}"
  echo ""
  echo "Guild-app"
  echo "========="
  echo "First deploy the app via ArgoCD (Refresh button), then use the URL"
  echo "URL: http://${NODE_IP_ADDRESS}:30082"

}


# Main

set -euo pipefail

run_in_script_dir
prerequisite_checks
determine_public_ip
terraform_init
terraform_deploy_k8s_cluster
terraform_deploy_crossplane_azure_family_provider
terraform_deploy_rest

echo ""
echo "==> Deployment complete."
echo ""

show_result