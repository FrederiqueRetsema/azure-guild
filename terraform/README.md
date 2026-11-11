# AKS + ArgoCD Terraform

Deploys an Azure Kubernetes Service (AKS) cluster, installs ArgoCD on it, and
creates an ArgoCD `Application` that tracks a configurable GitHub repository.

## Usage

Deploy the AKS cluster including ArgoCD with the guild-app:

```bash
# edit terraform.tfvars and set github_repo_url

cd terraform
bash deploy.sh
```
This will also expose the URLs for ArgoCD, the default password for the admin user and the demo app.

You can remove the AKS cluster via:

```bash
cd terraform
bash cleanup.sh
```
