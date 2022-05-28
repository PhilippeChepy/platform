# TL;DR

This repository implements a minimal PaaS hosted in Exoscale cloud.
This platform is based on Kubernetes and Vault.

### Global overview

![Global overview](doc/assets/Platform%402x.png)

# Packer

This platform relies on pre-configured instance templates.
This approach allows faster and simpler provisioning, as templates are preconfigured, and they ships some helper scripts.

## Templates

Each template is based on Ubuntu 22.04 (LTS)

- `exoscale-vault.pkr.hcl` (Vault 1.10.3)
    - Hashicorp Vault is used as a management system for most PKI, IAM, and other secrets for use by the whole infrastructure
- `exoscale-etcd.pkr.hcl` (Etcd 3.5.4):
    - Etcd is used as a data store for the Kubernetes control plane.
    - Vault agent to retrieve and update TLS certificates from the Vault cluster.
    - Helper script to create or join the cluster automatically, based on instance pool members.
- `exoscale-kube-controlplane.pkr.hcl` (Kubernetes 1.24.1 control plane):
    - Kubernetes control plane components: `apiserver`, `apiserver-network-proxy` (aka `konnectivity`), `scheduler`, `controller-manager`.
    - Vault agent to retrieve and update TLS certificates and other secrets from the Vault cluster.
- `exoscale-kube-node.pkr.hcl` (Kubernetes 1.24.1 node):
    - Kubelet service.
    - `kube-proxy` is NOT installed because the CNI plugin replaces its features (Cilium is deployed in the cluster in strict `kube-proxy` replacement mode).

## Build instructions

- From a terminal, move to the `packer` sub-directory.
- Create a `vars.hcl` file (template: `vars.hcl.example`), this file contains your Exoscale API key/secret.
- Initialize packer if you don't have the Exoscale Packer plugin (`packer init <packer-file>`).
- Build each template (`packer build -var-file vars.hcl <packer-file>), and take note of template IDs that will be used for the provisioning with Terraform.

```bash
cd packer
cp vars.hcl.example vars.hcl
vim vars.hcl
packer build -var-file vars.hcl exoscale-vault.pkr.hcl
# 【output】
# exoscale.base: output will be in this color.
#
# ==> exoscale.base: Build ID: ca8esk7m20rnv9j5gbmg
# ==> exoscale.base: Creating SSH key
# ==> exoscale.base: Creating Compute instance
# ==> exoscale.base: Using SSH communicator to connect: 194.182.170.167
# ==> exoscale.base: Waiting for SSH to become available...
# ==> exoscale.base: Connected to SSH!
# ==> exoscale.base: Provisioning with Ansible...
#     exoscale.base: Setting up proxy adapter for Ansible....
#
# ... truncated ...
#
# ==> exoscale.base: Stopping Compute instance
# ==> exoscale.base: Creating Compute instance snapshot
# ==> exoscale.base: Exporting Compute instance snapshot
# ==> exoscale.base: Registering Compute instance template
# ==> exoscale.base: Cleanup: destroying Compute instance
# ==> exoscale.base: Cleanup: deleting SSH key
# Build 'exoscale.base' finished after 5 minutes 2 seconds.
#
# ==> Wait completed after 5 minutes 2 seconds
#
# ==> Builds finished. The artifacts of successful builds are:
# --> exoscale.base: Vault 1.10.3 @ de-fra-1 (cf4a43f6-4fcd-455a-b023-82dc5133cdaa)

packer build -var-file vars.hcl exoscale-etcd.pkr.hcl
# 【output】
# exoscale.base: output will be in this color.
#
# ==> exoscale.base: Build ID: ca8esk7m20rnv9dlce60
# ==> exoscale.base: Creating SSH key
# ==> exoscale.base: Creating Compute instance
# ==> exoscale.base: Using SSH communicator to connect: 194.182.171.164
# ==> exoscale.base: Waiting for SSH to become available...
# ==> exoscale.base: Connected to SSH!
# ==> exoscale.base: Provisioning with Ansible...
#     exoscale.base: Setting up proxy adapter for Ansible....
#
# ... truncated ...
#
# ==> exoscale.base: Stopping Compute instance
# ==> exoscale.base: Creating Compute instance snapshot
# ==> exoscale.base: Exporting Compute instance snapshot
# ==> exoscale.base: Registering Compute instance template
# ==> exoscale.base: Cleanup: destroying Compute instance
# ==> exoscale.base: Cleanup: deleting SSH key
# Build 'exoscale.base' finished after 5 minutes 14 seconds.
#
# ==> Wait completed after 5 minutes 14 seconds
#
# ==> Builds finished. The artifacts of successful builds are:
# --> exoscale.base: Etcd 3.5.4 @ de-fra-1 (49ce56f8-d373-49c1-be05-e30c0cacb62e)

packer build -var-file vars.hcl exoscale-kube-controlplane.pkr.hcl
# 【output】
# exoscale.base: output will be in this color.
#
# ==> exoscale.base: Build ID: ca8esk7m20rnvf6phelg
# ==> exoscale.base: Creating SSH key
# ==> exoscale.base: Creating Compute instance
# ==> exoscale.base: Using SSH communicator to connect: 194.182.168.172
# ==> exoscale.base: Waiting for SSH to become available...
# ==> exoscale.base: Connected to SSH!
# ==> exoscale.base: Provisioning with Ansible...
#     exoscale.base: Setting up proxy adapter for Ansible....
#
# ... truncated ...
#
# ==> exoscale.base: Stopping Compute instance
# ==> exoscale.base: Creating Compute instance snapshot
# ==> exoscale.base: Exporting Compute instance snapshot
# ==> exoscale.base: Registering Compute instance template
# ==> exoscale.base: Cleanup: destroying Compute instance
# ==> exoscale.base: Cleanup: deleting SSH key
# Build 'exoscale.base' finished after 5 minutes 31 seconds.
#
# ==> Wait completed after 5 minutes 31 seconds
#
# ==> Builds finished. The artifacts of successful builds are:
# --> exoscale.base: Kubernetes 1.24.1 control plane @ de-fra-1 (a81b4643-da27-493f-98b0-b7f9fff7579b)

packer build -var-file vars.hcl exoscale-kube-node.pkr.hcl
# 【output】
# exoscale.base: output will be in this color.
#
# ==> exoscale.base: Build ID: ca8esk7m20rnvltdr6d0
# ==> exoscale.base: Creating SSH key
# ==> exoscale.base: Creating Compute instance
# ==> exoscale.base: Using SSH communicator to connect: 194.182.170.33
# ==> exoscale.base: Waiting for SSH to become available...
# ==> exoscale.base: Connected to SSH!
# ==> exoscale.base: Provisioning with Ansible...
#     exoscale.base: Setting up proxy adapter for Ansible....
#
# ... truncated ...
#
# ==> exoscale.base: Stopping Compute instance
# ==> exoscale.base: Creating Compute instance snapshot
# ==> exoscale.base: Exporting Compute instance snapshot
# ==> exoscale.base: Registering Compute instance template
# ==> exoscale.base: Cleanup: destroying Compute instance
# ==> exoscale.base: Cleanup: deleting SSH key
# Build 'exoscale.base' finished after 5 minutes 28 seconds.
#
# ==> Wait completed after 5 minutes 28 seconds
#
# ==> Builds finished. The artifacts of successful builds are:
# --> exoscale.base: Kubernetes 1.24.1 node @ de-fra-1 (f921e022-e7a9-4bf3-aa28-1ad34a46c2b1)
```

# Terraform

## Base components and secret management with Vault (terraform-base)

This configuration creates all required elements for other parts of the platform:
- a CA certificate and the related private key
- an operator security group (allows to access SSH, and clients of services: Vault, etcd, and Kubernetes API server)
- a SSH keypair
- a Vault cluster, which needs to be initialized and unsealed

### Overview

![Terraform base](doc/assets/terraform-base%402x.png)

### Module: vault

The Vault module allows to provision a Vault cluster:
- An anti-affinity group to ensure each cluster member goes to distinct hypervisors on the Exoscale side
- Two security groups: one for cluster members, another one for clients to be allowed to access the cluster
- A managed EIP as a final endpoint to reach the cluster
- An instance pool to ease template updates (doing a rolling update of each instance after having updated the instance pools template). By default, this instance pool size is 3, allowing to have a failing member.

### Post-provisioning tasks

- **TLS bootstrapping**. Before allowing any cluster operations, Vault needs a valid TLS certificate to start its API.
- **Cluster init and unseal operations**. Once provisioned, Vault must be [initialized](https://www.vaultproject.io/docs/commands/operator/init). This task should be done in only one instance. After initialization, each cluster member should be [unsealed](https://www.vaultproject.io/docs/commands/operator/unseal).

Both previous tasks can be performed using the `vault-cluster-bootstrap.yaml` Ansible playbook:

```bash
ansible-playbook -i artifacts/inventory_vault.yml playbooks/vault-cluster-bootstrap.yaml
```

## Base configuration (terraform-base-configuration)

This configuration creates the most required secrets and PKI secret engines in Vault, using the [Terraform Vault provider](https://registry.terraform.io/providers/hashicorp/vault/latest/docs).

It sets a PKI secret engine for Vault: the ICA path for this PKI is `pki/platform/vault`. This ICA is signed by the platform Root CA. 

### Secrets engines

| Engine Path                                | Role / Data                   | Policy                                         | Description                                     |
|--------------------------------------------|-------------------------------|------------------------------------------------|-------------------------------------------------|
| /iam/exoscale                              | etcd-instance-pool            | etcd                                           | IAM key for etcd cluster automatic setup
| /iam/exoscale                              | cloud-controller-manager      | cloud-controller-manager                       | IAM key for kubelet CSR validation
| /iam/exoscale                              | cluster-autoscaler            |                                                | **Not yet in use**
| /pki/root                                  |                               |                                                | **used by `terraform-kubernetes`** to signs /pki/platform/vault
| /pki/platform/vault                        | server                        | vault                                          | server certificate
| /pki/platform/kubernetes/etcd              | server                        | etcd                                           | server+client certificate
| /pki/platform/kubernetes/etcd              | apiserver                     | control-plane (api-server)                     | client certificate
| /pki/platform/kubernetes/control-plane     | apiserver                     | control-plane (api-server)                     | server certificate
| /pki/platform/kubernetes/control-plane     | controller-manager            | control-plane (controller-manager)             | client certificate
| /pki/platform/kubernetes/control-plane     | scheduler                     | control-plane (scheduler)                      | client certificate
| /pki/platform/kubernetes/control-plane     | cloud-controller-manager      | cloud-controller-manager                       | client certificate
| /pki/platform/kubernetes/control-plane     | konnectivity                  | control-plane (apiserver-network-proxy)        | client certificate, konnectivity
| /pki/platform/kubernetes/control-plane     | konnectivity-apiserver-egress | control-plane (api-server)                     | client certificate 
| /pki/platform/kubernetes/control-plane     | konnectivity-server-apiserver | control-plane (apiserver-network-proxy)        | server certificate, konnectivity
| /pki/platform/kubernetes/control-plane     | konnectivity-server-cluster   | control-plane (apiserver-network-proxy)        | server certificate, konnectivity
| /pki/platform/kubernetes/control-plane     | konnectivity-agent            |                                                | server certificate, **Not yet in use**
| /pki/platform/kubernetes/aggregation-layer | metrics-server                | metrics-server                                 | server certificate
| /pki/platform/kubernetes/aggregation-layer | apiserver                     | control-plane (api-server)                     | client certificate
| /pki/platform/kubernetes/kubelet           | apiserver                     | control-plane (api-server)                     | client certificate
| /pki/platform/kubernetes/client            | operator-admin                |                                                | client certificate, **used by `terraform-kubernetes`**
| /kv/platform/kubernetes                    | kubelet-pki                   | control-plane (controller-manager)             | secret: kubelet CA and private key
| /kv/platform/kubernetes                    | service-account               | control-plane (api-server, controller-manager) | secret: signing/verification key
| /kv/platform/kubernetes                    | secret-encryption             | control-plane (api-server)                     | secret: kubernetes secret encryption at rest
| /kv/platform/kubernetes                    | kubelet-bootstrap-token       |                                                | secret: token for kubelet bootstrapping process, **set in instances `user_data` by `terraform-kubernetes`**

### Authentication

| Auth engine    | Role                     | Authentication based on                                 |
|----------------|--------------------------|---------------------------------------------------------|
| /auth/exoscale | vault-server             | Security group: ${platform-name}-vault-server           |
| /auth/exoscale | etcd-server              | Security group: ${platform-name}-etcd-server            |
| /auth/exoscale | kubernetes-control-plane | Security group: ${platform-name}-kubernetes-controllers |

## Post-provisioning tasks

Once resources from this sub-directory are created, you can start vault-agent (`systemctl start vault-agent`) on each  vault instance. Vault agent will authenticate using the [Exoscale Vault authentication plugin](https://github.com/exoscale/vault-plugin-auth-exoscale). It will automatically renew Vault server certificates and reload the server service.

This task can be performed using the `vault-cluster-tls-agent.yaml` Ansible playbook:

```bash
ansible-playbook -i artifacts/inventory_vault.yml playbooks/vault-cluster-tls-agent.yaml
```

## Etcd & Kubernetes cluster (terraform-kubernetes)

This configuration creates an etcd cluster, a kubernetes control plane (2 nodes by default), and kubelet instance-pools.

![Terraform Kubernetes](doc/assets/terraform-kubernetes%402x.png)

This configuration also:
- deploys base deployments: `cilium`, `konnectivity`, `core-dns`, etc
- configure the Kubernetes authentication method in the Vault cluster for cert-manager (issues metrics-server server certificate), and for vault-agent-injector
to issue IAM keys for integration with Exoscale (`cloud-controller-manager` and `cluster-autoscaler`)

### Additional authentication setup

| Auth engine                           | Role                     | Authentication based on                                                          |
|---------------------------------------|--------------------------|----------------------------------------------------------------------------------|
| /auth/kubernetes/cert-manager         | metrics-server           | Service account: metrics-server (token: kube-system/metrics-server-vault-issuer) |
| /auth/kubernetes/vault-agent-injector | cloud-controller-manager | Service account: cloud-controller-manager (token: vault-server)                  |
| /auth/kubernetes/vault-agent-injector | cluster-autoscaler       | Service account: cluster-autoscaler (token: vault-server)                        |

## Provisioning instructions

- Create a `locals.tf` file (template: `locals.tf.example`) at the root of this repository.
- Export your Exoscale credentials as environment variables:
    ```bash
    export EXOSCALE_API_KEY="EXOxxxxxxxxxxxxxxxxxxxxxxxx"
    export EXOSCALE_API_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ```
- Create the base infrastructure:
    - Terraform: from the `terraform-base` sub-directory, run `terraform init` and `terraform apply`.
    - Ansible: from the **root directory**, run `ansible-playbook -i artifacts/inventory_vault.yml playbooks/vault-cluster-bootstrap.yaml`
- Configure the base infrastructure:
    - Terraform: from the `terraform-base-configuration` sub-directory, run `terraform init` and `terraform apply`.
    - Ansible: from the **root directory**, run `ansible-playbook -i artifacts/inventory_vault.yml playbooks/vault-cluster-tls-agent.yaml`
- Create the Kubernetes infrastructure:
    - Terraform: from the `terraform-kubernetes` sub-directory, run `terraform init` and `terraform apply`.
