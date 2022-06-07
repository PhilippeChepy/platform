# nginx ingress controller templates

How to build a new template:

```
VERSION=1.2.1
kustomize build ${VERSION} > "${VERSION}/manifests.yaml"
```