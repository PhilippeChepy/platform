# TL;DR

This repository implements various OS templates, for use in Exoscale cloud.
These templates are mostly used to implement a custom Kubernetes distribution.

Related repositories:
- [Terraform ETCD @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-etcd): contains an `etcd` HA cluster implementation @ Exoscale Cloud
- [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes): contains Kubernetes control plane implementation @ Exoscale Cloud
- [Terraform Kubelet Pool @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubelet-pool): contains a Kubernetes node pool implementation @ Exoscale Cloud
- [Example cluster](https://github.com/PhilippeChepy/kubernetes-exoscale-demo): an example of a deployment involving previously mentioned modules

# Templates

- etcd.pkr.hcl (Etcd 3.5.2):
    - Settings must be set in `/etc/default/etcd` when deploying.
- kube-controlplane.pkr.hcl (Kubernetes 1.23.4 control plane):
    - Lots of certificates must be set
    - Used by [Terraform Kubernetes @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubernetes)
- kube-node.pkr.hcl (Kubernetes 1.23.4 node):
    - TLS is bootstraped with a token
    - Used by [Terraform Kubelet Pool @ Exoscale](https://github.com/PhilippeChepy/terraform-exoscale-kubelet-pool)
- vault.pkr.hcl (Vault 1.9.3)

# Build instructions

- Create a `.vars.hcl` file (template: `.vars.hcl.example`), set your API keys/secrets inside.
- Initialize packer if you don't have the Exoscale Packer plugin (`packer init <packer-file>`)
- Build the template (`packer build -var-file .vars.hcl <packer-file>`)
