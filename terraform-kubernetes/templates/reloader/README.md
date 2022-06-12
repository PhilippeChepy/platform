# reloader template 

How to build a new template:

- update `kustomization.yaml` to match the expected version
- build manifests

```shell
VERSION=0.0.114

mkdir -p "${VERSION}"
kustomize build > "${VERSION}/manifests.yaml"
```