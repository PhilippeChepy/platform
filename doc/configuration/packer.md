# Packer

This platform relies on pre-configured instance templates.
This approach allows faster and simpler provisioning, as templates are preconfigured, and they ship some helper scripts.

## Templates

Each template is based on Ubuntu 22.04 (LTS)

- `exoscale-vault.pkr.hcl` (Vault 1.12.0)
    - Hashicorp Vault is used as a management system for most PKI, IAM, and other secrets for use by the whole infrastructure
- `exoscale-etcd.pkr.hcl` (Etcd 3.5.5):
    - Etcd is used as a data store for the Kubernetes control plane.
    - Vault agent to retrieve and update TLS certificates from the Vault cluster.
    - Helper script to create or join the cluster automatically, based on instance pool members.
- `exoscale-kube-controlplane.pkr.hcl` (Kubernetes 1.25.2 control plane):
    - Kubernetes control plane components: `apiserver`, `apiserver-network-proxy` (aka `konnectivity`), `scheduler`, `controller-manager`.
    - Vault agent to retrieve and update TLS certificates and other secrets from the Vault cluster.
- `exoscale-kube-node.pkr.hcl` (Kubernetes 1.25.2 node):
    - Kubelet service.
    - `kube-proxy` is NOT installed because the CNI plugin replaces its features (Cilium is deployed in the cluster in strict `kube-proxy` replacement mode).

## Build instructions

See [the initial provisioning runbook for build instructions](../runbooks/Initial-Provisioning.md#build-instances-templates-using-packer).
