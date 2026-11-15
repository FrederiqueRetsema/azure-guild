#!/bin/bash
sleep 100
kubectl -n portable-app get instance.ec2.aws.m.upbound.io guild-vm -o jsonpath='{.status.atProvider.publicIp}{"\n"}'
kubectl -n portable-app get events --field-selector involvedObject.name=guild-vm 2>&1 | grep -i -E "Updated|Created" | tail
curl -s -m 8 -o /dev/null -w "HTTP %{http_code}\n" http://$(kubectl -n portable-app get instance.ec2.aws.m.upbound.io guild-vm -o jsonpath='{.status.atProvider.publicIp}')/
