#!/usr/bin/env bash
#
# Usage:
#   ./deploy.sh [aws-profile]
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

  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is not installed or not on PATH (needed to detect the public IP)." >&2
    exit 1
  }

  if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" >/dev/null 2>&1; then
    echo "ERROR: Not logged in to AWS with profile '${AWS_PROFILE}'. Run 'aws sso login --profile ${AWS_PROFILE}' first." >&2
    exit 1
  fi

  if [ ! -f terraform.tfvars ] && [ -z "${TF_VAR_github_repo_url:-}" ]; then
    echo "ERROR: github_repo_url is not set." >&2
    echo "       Create terraform.tfvars" >&2
    echo "       or export TF_VAR_github_repo_url=<url>." >&2
    exit 1
  fi

  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --profile ${AWS_PROFILE})"
  echo "Using AWS profile ${AWS_PROFILE}, account: ${AWS_ACCOUNT_ID}"

}


function determine_public_ip() {

  echo "==> Determining the public IP address of this machine"

  local ip=""
  for url in "https://checkip.amazonaws.com" "https://api.ipify.org" "https://ifconfig.me/ip"; do
    ip="$(curl -fsS --max-time 10 "$url" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$ip" ]; then
      break
    fi
  done

  if [ -z "$ip" ]; then
    echo "ERROR: Could not determine the public IP address of this machine." >&2
    exit 1
  fi

  if ! echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
    echo "ERROR: Detected value '${ip}' does not look like a valid IPv4 address." >&2
    exit 1
  fi

  export TF_VAR_nodeport_source_cidr="${ip}/32"
  echo "Public IP detected: ${ip}"
  echo "Restricting NodePort source CIDR to: ${TF_VAR_nodeport_source_cidr}"

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
    -target=aws_eks_cluster.this \
    -target=aws_eks_node_group.default \
    -target=helm_release.argocd \
    -target=helm_release.crossplane

}


function terraform_deploy_crossplane_aws_family_provider() {

  # The family and service providers are applied together: the service
  # providers require the family provider at exactly their own version. When
  # only the family provider is upgraded, Crossplane installs a second family
  # provider to satisfy the old service providers and dependency resolution
  # gets stuck, so none of them become healthy.
  echo "==> Phase 2: Crossplane AWS family and service providers"
  terraform apply -input=false -auto-approve \
    -target=kubernetes_manifest.crossplane_provider_family_aws \
    -target=kubernetes_manifest.crossplane_provider_aws_service

  REGION="$(terraform console <<<'var.region' | tr -d '"')"
  CLUSTER_NAME="$(terraform console <<<'var.cluster_name' | tr -d '"')"
  aws eks update-kubeconfig \
    --region "$REGION" \
    --name "$CLUSTER_NAME" \
    --profile "${AWS_PROFILE}" >/dev/null

  echo "==> Waiting for the Crossplane providers to become healthy"
  kubectl wait --for=condition=Healthy provider.pkg.crossplane.io --all \
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

select_aws_profile "$@"
run_in_script_dir
prerequisite_checks
determine_public_ip
terraform_init
terraform_deploy_k8s_cluster
terraform_deploy_crossplane_aws_family_provider
terraform_deploy_rest

echo ""
echo "==> Deployment complete."
echo ""

show_result
