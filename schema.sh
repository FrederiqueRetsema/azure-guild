#!/bin/bash
kubectl get flexibleserverfirewallrule.dbformysql.azure.upbound.io azure-guild-mysql-allow-azure -o jsonpath='{.status.conditions}'
echo
echo "--- server ---"
kubectl get flexibleserver.dbformysql.azure.upbound.io azure-guild-mysql -o jsonpath='{.status.conditions}'
