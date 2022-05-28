# Vault Agent Injector template 

How to build a new template:

```shell
helm repo add hashicorp https://helm.releases.hashicorp.com

VERSION=0.16.1

mkdir -p "${VERSION}"

helm template vault hashicorp/vault \
  --namespace vault-agent-injector \
  -f values.yaml \
    > "${VERSION}/manifests.yaml"

cat vault-sa.yaml >> "${VERSION}/manifests.yaml"
```

From Kubernetes 1.24, tokens lifetime is tied to Pod lifetime by default, so we have to explicitely create a token
to have a token which is not bound in time.
Before Kubernetes 1.24, cloud controller manager generated default tokens have a random name, so this one allows to easily
query the API Server for signed token value.  