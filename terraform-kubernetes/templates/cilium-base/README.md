# Cilium template 

How to build a new template:

```shell
helm repo add cilium https://helm.cilium.io/

VERSION=1.11.5

mkdir -p "${VERSION}"
helm template cilium cilium/cilium --version "${VERSION}" \
  --namespace kube-system \
  -f values.yaml \
    > "${VERSION}/manifests.yaml"

cat pdb.yaml >> "${VERSION}/manifests.yaml"
```