kubectl get functions.pkg.crossplane.io 2>&1
echo ---
kubectl get functionrevisions.pkg.crossplane.io 2>&1
echo ---
kubectl get pods -A 2>&1 | grep -i -E "function|crossplane|NAME"
