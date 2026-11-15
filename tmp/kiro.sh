#!/bin/bash
kubectl config current-context
kubectl get virtualmachines.apps.azure-guild.io -A
kubectl get publicip,securitygroup,networkinterface,networkinterfacesecuritygroupassociation,linuxvirtualmachine -A 2>&1 | head -50
