# AKS + ArgoCD Terraform

Deploys an Azure Kubernetes Service (AKS) cluster, installs ArgoCD on it, and
creates an ArgoCD `Application` that tracks a configurable GitHub repository.

## What gets created

- A resource group (default: `frederique-azure-guild`)
- An AKS cluster with a system-assigned managed identity
- ArgoCD, installed via the official `argoproj/argo-helm` chart
- An ArgoCD `Application` pointing at your GitHub repo, with automated
  self-healing sync enabled
- Crossplane, installed via the official `crossplane-stable` Helm chart

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.9
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), logged
  in via `az login --tenant <tenant-id>`

Terraform authenticates to Azure through the Azure CLI session.

## Usage

Deploy the AKS cluster including ArgoCD with the guild-app:

```bash
# edit terraform.tfvars and set github_repo_url

cd terraform
bash deploy.sh
```
This will also expose the URLs for ArgoCD and the demo app.

You can remove the AKS cluster via:

```bash
cd terraform
bash cleanup.sh
```

### Azure provider

With `install_crossplane_azure_provider = true` (default), Terraform installs
the Upbound Azure family provider (`provider-family-azure`) plus the service
packages listed in `crossplane_azure_service_providers` (default:
`resources`, `network`, `storage`, `dbformysql`), all pinned to
`crossplane_azure_provider_version` (default `v2.8.0`). The `dbformysql`
package provides the CRDs used by the MySQL Flexible Server managed resources
in [`../crossplane-managed-resource`](../crossplane-managed-resource).

To let Crossplane authenticate to Azure, supply a service-principal credentials
JSON. Generate it and pass it in via an environment variable so it never lands
in a file:

```bash
az ad sp create-for-rbac --sdk-auth --role Owner \
  --scopes /subscriptions/<subscription-id> > azure-credentials.json

export TF_VAR_crossplane_azure_credentials_json="$(cat azure-credentials.json)"
terraform apply
```

When the credentials JSON is provided, Terraform creates a `Secret`
(`azure-secret` in the Crossplane namespace) and a `ProviderConfig` named by
`crossplane_azure_providerconfig_name` (default `default`). Leave the variable
empty to install only the provider packages and wire credentials up yourself
later.

Verify the providers become healthy:

```bash
kubectl get providers
```

> **First-apply ordering:** `kubernetes_manifest` reads CRDs at plan time, so a
> clean cluster needs a phased apply. `deploy.sh` does this for you:
>
> 1. cluster + `helm_release.argocd` + `helm_release.crossplane`
>    (installs the `argoproj.io` and `pkg.crossplane.io` CRDs)
> 2. `kubernetes_manifest.crossplane_provider_family_azure`, then waits for the
>    provider to be `Healthy` (installs the `azure.upbound.io` CRDs)
> 3. the full `terraform apply`
>
> If you run Terraform by hand, repeat those steps with `-target`.

### MySQL Flexible Server (Crossplane managed resources)

[`../crossplane-managed-resource/mysql-flexible-server.yaml`](../crossplane-managed-resource/mysql-flexible-server.yaml)
defines an Azure Database for MySQL Flexible Server as Crossplane managed
resources (a `FlexibleServer`, a `FlexibleServerFirewallRule`, a
`FlexibleDatabase`, and the admin-password `Secret`). They use the
cluster-scoped `dbformysql.azure.upbound.io` API group and the `default`
`ProviderConfig`, so they rely on the `dbformysql` service provider being
installed (included in the default `crossplane_azure_service_providers`).

Once the providers are `Healthy`, apply the manifest:

```bash
kubectl apply -f ../crossplane-managed-resource/mysql-flexible-server.yaml
kubectl get flexibleserver.dbformysql.azure.upbound.io guild-mysql
```

> Before applying, replace the demo password in the `Secret` and make sure the
> server's `crossplane.io/external-name` is globally unique under
> `.mysql.database.azure.com`.

## Notes

- The `kubernetes` and `helm` providers are configured directly from the AKS
  cluster credentials Terraform produces, so no manual kubeconfig step is
  needed for `apply`.
- The ArgoCD `Application` uses `kubernetes_manifest`, which reads the ArgoCD
  CRDs at plan time. The CRDs must exist before the manifest is planned; the
  Helm release installs them and the `depends_on` enforces ordering. If you hit
  a CRD-not-found error on a first-ever apply, run
  `terraform apply -target=helm_release.argocd` once, then a full
  `terraform apply`.
