# DeploymentAndService Crossplane composition

A Crossplane v2 composition that packages a `Deployment` and a `Service` behind
a single generic custom API, `DeploymentAndService`. Creating one XR makes
Crossplane compose both Kubernetes objects.

This targets the Crossplane version installed by the Terraform in this repo
(chart `2.4.3`, i.e. Crossplane v2). In v2, composite resources are namespaced
and can compose native Kubernetes resources directly, so no
`provider-kubernetes` `Object` wrapper is needed.

## Files

| File                | Purpose                                                                           |
| ------------------- | --------------------------------------------------------------------------------- |
| `xrd.yaml`          | `CompositeResourceDefinition` defining the `DeploymentAndService` API and schema  |
| `functions.yaml`    | Installs `function-patch-and-transform`, used by the composition                   |
| `composition.yaml`  | `Composition` (`deployment-and-service`) mapping the XR to a `Deployment` + `Service` |
| `wordpress.yaml`    | Example XR running WordPress                                                        |

## The DeploymentAndService API

```yaml
apiVersion: apps.azure-guild.io/v1alpha1
kind: DeploymentAndService
metadata:
  name: wordpress
  namespace: default
spec:
  image: wordpress:6.7-apache # container image (required)
  replicas: 2 # Deployment replicas
  containerPort: 80 # container port
  servicePort: 80 # Service port
  serviceType: NodePort # ClusterIP | NodePort | LoadBalancer
  nodePort: 30080 # NodePort (only used when serviceType: NodePort)
```

Only `image` is required; the rest have defaults.

## Apply

Crossplane must already be installed on the cluster (the repo's Terraform does
this). Then:

```bash
# 1. install the composition function
kubectl apply -f functions.yaml

# wait for it to report HEALTHY
kubectl get functions

# 2. register the API and the composition
kubectl apply -f xrd.yaml
kubectl apply -f composition.yaml

# 3. create an instance
kubectl apply -f wordpress.yaml
```

## Verify

```bash
# the XR itself
kubectl get deploymentandservice wordpress

# the composed resources (labelled with the XR name)
kubectl get deploy,service -l app.azure-guild.io/instance=wordpress
```

## Clean up

```bash
# deleting the XR removes the composed Deployment and Service
kubectl delete -f wordpress.yaml

kubectl delete -f composition.yaml
kubectl delete -f xrd.yaml
kubectl delete -f functions.yaml
```

## Note on the WordPress demo

WordPress needs a MySQL/MariaDB database to complete setup. This composition
only produces the WordPress `Deployment` + `Service`; it does not provision a
database. To get a fully working WordPress you can either run a database in the
cluster (or use a managed one) and point WordPress at it, or extend the
composition to inject the `WORDPRESS_DB_HOST` / `WORDPRESS_DB_USER` /
`WORDPRESS_DB_PASSWORD` / `WORDPRESS_DB_NAME` environment variables. The example
keeps the focus on the generic Deployment + Service pattern.
