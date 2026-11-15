# Required
github_repo_url = "https://github.com/FrederiqueRetsema/azure-guild.git"

# Optional overrides (defaults shown).
# region             = "eu-west-1"
# cluster_name       = "aws-guild-eks"
# node_count         = 2
# node_instance_type = "t3.medium"
# kubernetes_version = "1.37"

# github_repo_revision = "HEAD"
# argocd_app_namespace = "default"
# argocd_chart_version = "8.3.0"

# Path in the repository with the Crossplane managed resources. The default
# directory contains Azure resources; point it to AWS manifests (for example an
# RDS MySQL instance) when deploying on AWS.
# crossplane_managed_resource_path = "crossplane-managed-resource"

# Crossplane AWS service providers. "rds" is needed for MySQL managed resources.
# crossplane_aws_service_providers = ["ec2", "rds", "s3"]
