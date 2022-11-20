# CoreDNS template 

How to build a new template:
- you need to have `helm` and `kustomize` cli tools installed
- update the `kustomization.yaml` file to match the new version
- render the manifest bundle file: `kustomize build --enable-helm . > manifests.yaml`
