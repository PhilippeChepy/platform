# Cert-Manager template 

How to build a new template:

```shell
helm repo add jetstack https://charts.jetstack.io

VERSION=1.8.0

mkdir -p "${VERSION}"
helm template cert-manager jetstack/cert-manager --version "${VERSION}" \
  --namespace cert-manager \
  -f values.yaml \
    > "${VERSION}/manifests.yaml"
```