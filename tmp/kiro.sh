#!/bin/bash
aws ec2 describe-instances --region eu-west-1 --instance-ids i-0d28fff67fc3f9568 --query 'Reservations[0].Instances[0].{state:State.Name,pub:PublicIpAddress,subnet:SubnetId,sgs:SecurityGroups,type:InstanceType}' --output json
echo ---SG
aws ec2 describe-security-group-rules --region eu-west-1 --filters Name=group-id,Values=sg-095a36061a194c3f7 --query 'SecurityGroupRules[].{egress:IsEgress,proto:IpProtocol,from:FromPort,to:ToPort,cidr:CidrIpv4}' --output json
echo ---ROUTE
aws ec2 describe-route-tables --region eu-west-1 --filters Name=association.subnet-id,Values=subnet-0ca4fbf119bafb619 --query 'RouteTables[].Routes' --output json
echo ---NACL
aws ec2 describe-network-acls --region eu-west-1 --filters Name=association.subnet-id,Values=subnet-0ca4fbf119bafb619 --query 'NetworkAcls[].Entries' --output json
echo ---CONSOLE
aws ec2 get-console-output --region eu-west-1 --instance-id i-0d28fff67fc3f9568 --latest --output text | tail -60
