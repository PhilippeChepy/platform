# TL;DR

This repository implements a minimal PaaS hosted in the Exoscale public cloud.
This platform is based on:
- Hashicorp Vault for secret management
- Kubernetes for workloads orchestration

### Global overview

![Global overview](doc/assets/Platform%402x.png)

### Runbooks

- [Full provisioning instructions](./doc/Initial-Provisioning.md)
- [Building a fresh Vault snapshot & retrieving it locally](./doc/Snapshots.md#vault-snapshots)
- [Building a fresh Etcd snapshot & retrieving it locally](./doc/Snapshots.md#etcd-snapshots)
- [Upgrading the Vault cluster](./doc/Upgrade-Vault-Instances.md)
- [Upgrading the Etcd cluster](./doc/Upgrade-Kubernetes-Datastore.md)
- [Upgrading the Kubernetes control plane](./doc/Upgrade-Kubernetes-ControlPlane.md)
- [Upgrading the Kubernetes Nodes instance pools](./doc/Upgrade-Kubernetes-Node-InstancePool.md)
- [Disaster Recovery: Vault](./doc/DisasterRecovery-Vault.md)
- [Disaster Recovery: Etcd](./doc/DisasterRecovery-Etcd.md)
- [Destroying the whole infrastructure](./doc/Destroy-Everything.md)

### Additional documentation

- Official [Vault disaster recovery procedure](https://learn.hashicorp.com/tutorials/vault/sop-restore#single-vault-cluster) from Hashicorp Learn
- Official [Etcd disaster recovery procedure](https://etcd.io/docs/v3.5/op-guide/recovery/) from etcd.io documentation

### Known issues (and workarounds)

- [Expired Kubernetes admin client configuration](./doc/Known-Issues.md#expired-kubernetes-admin-client-configuration)

# Packer

This platform relies on pre-configured instance templates.
This approach allows faster and simpler provisioning, as templates are preconfigured, and they ship some helper scripts.

## Templates

Each template is based on Ubuntu 22.04 (LTS)

- `exoscale-vault.pkr.hcl` (Vault 1.11.2)
    - Hashicorp Vault is used as a management system for most PKI, IAM, and other secrets for use by the whole infrastructure
- `exoscale-etcd.pkr.hcl` (Etcd 3.5.4):
    - Etcd is used as a data store for the Kubernetes control plane.
    - Vault agent to retrieve and update TLS certificates from the Vault cluster.
    - Helper script to create or join the cluster automatically, based on instance pool members.
- `exoscale-kube-controlplane.pkr.hcl` (Kubernetes 1.24.3 control plane):
    - Kubernetes control plane components: `apiserver`, `apiserver-network-proxy` (aka `konnectivity`), `scheduler`, `controller-manager`.
    - Vault agent to retrieve and update TLS certificates and other secrets from the Vault cluster.
- `exoscale-kube-node.pkr.hcl` (Kubernetes 1.24.3 node):
    - Kubelet service.
    - `kube-proxy` is NOT installed because the CNI plugin replaces its features (Cilium is deployed in the cluster in strict `kube-proxy` replacement mode).

## Build instructions

See [the initial provisioning runbook for build instructions](./doc/Initial-Provisioning.md#build-instances-templates-using-packer).

# Terraform

Terraform configurations:
- depend on the `locals.tf` file, located at the root of this repository,
- creates some secret files in the `artifacts` subdirectory

The whole infrastructure is provisioned by applying 5 configurations, one after another:
- `terraform-base`: for the Vault infrastructure
- `terraform-base-configuration`: for the Vault configuration
- `terraform-kubernetes`: for the Etcd and Kubernetes infrastructure
- `terraform-kubernetes-deployments-bootstrap`: for required Kubernetes deployments
- `terraform-kubernetes-deployments-core`: for core Kubernetes and ingress-controller deployments

Additionally, integration with Cloudflare is set by applying an additional configuration:
- `terraform-kubernetes-deployments-ingress-cloudflare`: deploys external-DNS and lets-encrypt integration using DNS01 issuer

## Base components and secret management with Vault (terraform-base)

This configuration creates all required elements for other parts of the platform:
- a CA certificate and the related private key
- an operator security group (allows to access SSH, and clients of services: `Hashicorp Vault`, `Etcd`, and `Kubernetes` API server)
- an SSH keypair
- a Vault cluster, which needs to be initialized and unsealed

### Overview

![Terraform base](doc/assets/terraform-base%402x.png)

### Module: vault

The Vault module allows the provisioning of a Vault cluster:
- An anti-affinity group to ensure each cluster member goes to distinct hypervisors on the Exoscale side
- Two security groups: one for cluster members, another one for clients to be allowed to access the cluster
- A managed EIP as a final endpoint to reach the cluster
- An instance pool to ease template updates (doing a rolling update of each instance after having updated the instance pools template). By default, this instance pool size is 3, allowing to have a failing member.

### Post-provisioning tasks

- **TLS bootstrapping**. Before allowing any cluster operations, Vault needs a valid TLS certificate to start its API.
- **Cluster init and unseal operations**. Once provisioned, Vault must be [initialized](https://www.vaultproject.io/docs/commands/operator/init). This task should be done in only one instance. After initialization, each cluster member should be [unsealed](https://www.vaultproject.io/docs/commands/operator/unseal).

Both previous tasks can be performed using the `vault-cluster-bootstrap.yaml` Ansible playbook:

```bash
ansible-playbook -i artifacts/inventory.yml playbooks/vault-cluster-bootstrap.yaml
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

Once resources from this sub-directory are created, you can start vault-agent (`systemctl start vault-agent`) on each vault instance. Vault agent will authenticate using the [Exoscale Vault authentication plugin](https://github.com/exoscale/vault-plugin-auth-exoscale). It will automatically renew Vault server certificates and reload the server service.

This task can be performed using the `vault-cluster-tls-agent.yaml` Ansible playbook:

```bash
ansible-playbook -i artifacts/inventory.yml playbooks/vault-cluster-tls-agent.yaml
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

See [the initial provisioning runbook for provisioning instructions](./doc/Initial-Provisioning.md#provision-the-infrastructure-using-terraform).
