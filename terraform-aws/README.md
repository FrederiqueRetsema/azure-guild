# EKS + ArgoCD + Crossplane Terraform (AWS)

Deploys an Amazon EKS cluster (own VPC, managed node group), installs ArgoCD and
Crossplane (with the Upbound AWS provider) on it, and creates ArgoCD
`Application`s that track a configurable GitHub repository. This is the AWS
counterpart of `../terraform-azure`.

## Prerequisites

- `terraform`, `aws` CLI, `kubectl` and `curl` on the PATH.
- A logged-in AWS profile that can create VPC, EKS, IAM and EC2 resources. The
  scripts use the profile `xforce-sandbox1` by default (`aws sso login --profile
  xforce-sandbox1`); pass another profile as the first argument, for example
  `bash deploy.sh my-profile`.
- The default region is `eu-west-1` (variable `region`).

## Usage

Deploy the EKS cluster including ArgoCD with the guild-app:

```bash
# edit terraform.tfvars and set github_repo_url

cd terraform-aws
bash deploy.sh
```
This will also expose the URLs for ArgoCD, the default password for the admin user and the demo app.

You can remove the EKS cluster via:

```bash
cd terraform-aws
bash cleanup.sh
```

## Notes

- Terraform creates an IAM user for Crossplane (`crossplane_aws_iam_user_name`)
  and stores its access key in the `aws-secret` Secret that the Crossplane
  `ProviderConfig` uses.
- The ArgoCD application `crossplane-managed-resource` tracks the directory in
  `crossplane_managed_resource_path`. The default `crossplane-managed-resource`
  contains Azure resources, so set this variable to a directory with AWS
  manifests before deploying the database part on AWS.

## portable-app

ArgoCD deploys `portable-app/common` and `portable-app/aws` (namespace
`portable-app`). This creates, via Crossplane compositions, a VPC with nine
subnets (public, private and data, one per availability zone `a`, `b` and `c`)
named `guild-network`, an AlmaLinux EC2 instance in the first public subnet
(`guild-vm`) and an RDS MySQL instance in the data subnets (`guild-databaseserver`).

The AlmaLinux AMI IDs are pinned per region in
`portable-app/aws/composition-virtualmachine.yaml` (eu-west-1, eu-central-1 and
us-east-1). Update them from <https://wiki.almalinux.org/cloud/AWS.html> when a
newer image is wanted.
