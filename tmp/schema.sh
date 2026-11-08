#!/bin/bash
set -e
kubectl get crd flexibleservers.dbformysql.azure.upbound.io -o json \
  | jq -r '.spec.versions[] | select(.name=="v1beta2") | .schema.openAPIV3Schema.properties.spec.properties.forProvider.properties.storage'
