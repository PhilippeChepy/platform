# TL;DR

This repository implements various OS templates, for use in Exoscale cloud.
These templates are mostly used to implement a custom Kubernetes distribution.

Related repositories:
- [Terraform ETCD @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-etcd): contains an `etcd` HA cluster implementation @ Exoscale Cloud
- [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes): contains Kubernetes control plane implementation @ Exoscale Cloud
- [Terraform Kubelet Pool @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubelet-pool): contains a Kubernetes node pool implementation @ Exoscale Cloud
- [Example cluster](https://github.com/PhilippeChepy/kubernetes-exoscale-demo): an example of a deployment involving previously mentioned modules

# Templates

Every templates are based on Ubuntu 22.04 (LTS)

- `vault.pkr.hcl` (Vault 1.10.3)
    - Hashicorp Vault is used as base for most PKI, IAM and other secret things in the whole target infrastructure
- `etcd.pkr.hcl` (Etcd 3.5.4):
    - Etcd is used as datastore for the Kubernetes control plane.
    - Hashicorp Vault as agent to manage etcd TLS certificates.
    - Automatic management of the cluster, based on instance pool informations.
- `kube-controlplane.pkr.hcl` (Kubernetes 1.24.0 control plane):
    - Kubernetes control plane components (apiserver, konnectivity, scheduler, controller-manager).
    - Hashicorp Vault as agent to manage control plane, aggregation layer, kubelet and client TLS certificates.
- `kube-node.pkr.hcl` (Kubernetes 1.24.0 node):
    - Kubelet (Kubernetes node) service.
    - No kube-proxy setup as it's expected to be handled by the CNI plugin that would be deployed (e.g. Cilium with strict
    kube-proxy replacement).
    - Hashicorp Vault as agent to manage kubelet TLS certificates.

# Build instructions

- Create a `.vars.hcl` file (template: `.vars.hcl.example`), set your API keys/secrets inside.
- Initialize packer if you don't have the Exoscale Packer plugin (`packer init <packer-file>`)
- Build the template (`packer build -var-file .vars.hcl <packer-file>`)
