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

```bash
# edit terraform.tfvars and set github_repo_url

terraform init
terraform plan
terraform apply
```

## After apply

Fetch kubeconfig credentials:

```bash
az aks get-credentials --resource-group frederique-azure-guild --name azure-guild-aks
```

Get the ArgoCD initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Access the ArgoCD UI. With `expose_argocd_nodeport = true` (the default), the
server is published on a NodePort, so browse directly to a node's public IP:

```bash
kubectl get nodes -o wide   # grab an EXTERNAL-IP
# then open https://<node-ip>:30082 (HTTPS) or http://<node-ip>:30081 (HTTP)
```

Alternatively, use a port-forward without exposing anything publicly:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Then open https://localhost:8080 and log in as `admin`.

## Public NodePort access

The sample app in `guild-app/` is exposed via a `NodePort` Service on port
`30080`. To make it reachable from the public internet, Terraform:

- enables `node_public_ip_enabled` on the default node pool so each node gets a
  public IP, and
- adds an inbound rule to the AKS-managed node NSG allowing TCP on the NodePort.

After apply, find a node's public IP and browse to it:

```bash
kubectl get nodes -o wide   # look at the EXTERNAL-IP column
# then open http://<node-ip>:30080
```

The ArgoCD server is exposed the same way on ports `30081` (HTTP) and `30082`
(HTTPS), controlled by `expose_argocd_nodeport`.

To lock access down to your own IP, set
`nodeport_source_address_prefix = "<your-ip>/32"` (it applies to both the app
and ArgoCD rules). To disable public exposure entirely, set
`expose_nodeport = false` and/or `expose_argocd_nodeport = false`.

> Enabling node public IPs cycles the default node pool, so the first apply of
> this change will recreate the nodes.

## Crossplane

Crossplane is installed from the official `crossplane-stable` Helm chart into
the `crossplane-system` namespace (version `2.4.3`). It installs the Crossplane
controllers and core CRDs; you then add providers (e.g. the Azure provider) and
compositions on top. To disable it, set `install_crossplane = false`.

Verify it is running:

```bash
kubectl get pods -n crossplane-system
```

### Azure provider

With `install_crossplane_azure_provider = true` (default), Terraform installs
the Upbound Azure family provider (`provider-family-azure`) plus the service
packages listed in `crossplane_azure_service_providers` (default:
`resources`, `network`, `storage`), all pinned to
`crossplane_azure_provider_version` (default `v2.8.0`).

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
