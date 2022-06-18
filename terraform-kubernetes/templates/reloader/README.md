# Reloader template 

How to build a new template:
- you need to have the `kustomize` cli tool installed
- create a new version directory, based on the latest
- update the `kustomization.yaml` file to match the new version
- render the manifest bundle file: `kustomize build ./<new-version>/ > <new-version>/manifests.yaml`
