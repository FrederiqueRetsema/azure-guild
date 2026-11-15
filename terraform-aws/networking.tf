# EKS attaches the cluster security group to the managed node group nodes, so
# the NodePort rules go on that group.

resource "aws_vpc_security_group_ingress_rule" "guildapp_nodeport" {
  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "allow-nodeport-${var.guildapp_nodeport_http}"

  ip_protocol = "tcp"
  from_port   = var.guildapp_nodeport_http
  to_port     = var.guildapp_nodeport_http
  cidr_ipv4   = var.nodeport_source_cidr

  depends_on = [aws_eks_node_group.default]
}

resource "aws_vpc_security_group_ingress_rule" "argocd_nodeport" {
  for_each = {
    http  = var.argocd_nodeport_http
    https = var.argocd_nodeport_https
  }

  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description       = "allow-argocd-nodeport-${each.key}"

  ip_protocol = "tcp"
  from_port   = each.value
  to_port     = each.value
  cidr_ipv4   = var.nodeport_source_cidr

  depends_on = [aws_eks_node_group.default]
}
