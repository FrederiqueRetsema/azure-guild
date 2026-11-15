# AKS + ArgoCD Terraform

Deploys an Azure Kubernetes Service (AKS) cluster, installs ArgoCD on it, and
creates an ArgoCD `Application` that tracks a configurable GitHub repository.

## Usage

Deploy the AKS cluster including ArgoCD with the guild-app:

```bash
# edit terraform.tfvars and set github_repo_url

cd terraform-azure
bash deploy.sh
```
This will also expose the URLs for ArgoCD, the default password for the admin user and the demo app.

You can remove the AKS cluster via:

```bash
cd terraform-azure
bash cleanup.sh
```

## portable-app

ArgoCD deploys `portable-app/common` and `portable-app/azure` (namespace
`portable-app`). This creates, via Crossplane compositions, a VNet with a public,
private and data subnet (`guild-network`), an AlmaLinux VM in the public subnet
(`guild-vm`) and a MySQL flexible server with private access in the data subnet
(`guild-databaseserver`).

Before the VM can be created, accept the AlmaLinux marketplace terms once per
subscription:

```bash
az vm image terms accept --publisher almalinux --offer almalinux-x86_64 --plan 10-gen2
```
