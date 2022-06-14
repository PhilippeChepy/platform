# external-dns template 

How to build a new template:

- update `kustomization.yaml` to match the expected version
- build manifests

```shell
VERSION=0.12.0

mkdir -p "${VERSION}"
kustomize build > "${VERSION}/manifests.yaml"
```