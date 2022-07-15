# nginx ingress controller templates

How to build a new template:

```
VERSION=1.3.0
kustomize build ${VERSION} > "${VERSION}/manifests.yaml"
```