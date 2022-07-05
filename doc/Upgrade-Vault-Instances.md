# Hashicorp Vault cluster upgrade procedure

**IMPORTANT** First, you need to perform a backup of your Vault cluster, this would help you easily rollback in case of disaster.
Once your backup is made and stored in a safe location, you can proceed with the next steps.

1. Build the new Vault template:
  - move to the `packer` directory
  - run packer: `packer build -var-file vars.hcl exoscale-vault.pkr.hcl`
  - grab the template ID from the output: `--> exoscale.base: Vault 1.10.4 @ de-fra-1 (cf4a43f6-4fcd-455a-b023-82dc5133cdaa)`
2. Update the Vault instance-pool:
  - Update the value for `platform_components.vault.template` in your `locals.tf` file with the template ID from step 1. Keep the older
  value for the cleanup step
  - move to the `terraform-base` directory
  - run `terraform apply`, this should update the instance-pool template ID
3. With `exo` CLI, or by other means, get the list of current Vault instances. These instances are using the old template:
    ```bash  
    exo compute instance list |grep vault
    # 【output】
    # | 88fb64e0-d04f-4834-9e40-8201ed363706 | paas-staging-vault-addab-jppqr            | de-fra-1 | standard.tiny  | 89.145.162.86   | running |
    # | 08763871-0de4-4bb6-b175-64634f3bf51c | paas-staging-vault-addab-ndksc            | de-fra-1 | standard.tiny  | 194.182.169.86  | running |
    # | 1de9120c-4115-494d-af42-c887d9232f77 | paas-staging-vault-addab-slqku            | de-fra-1 | standard.tiny  | 89.145.163.92   | running |
    ```
4. With `exo` CLI, or by other means, delete an instance belonging to the list found in step 3.
    ```bash
    exo compute instance delete paas-staging-vault-addab-jppqr
    # 【output】
    # [+] Are you sure you want to delete instance "paas-staging-vault-addab-jppqr"? [yN]: y
    # ✔ Deleting instance "paas-staging-vault-addab-jppqr"... 9s
    ```
5. A new instance will be automatically created to replace the one you just deleted:
  - Wait for the new instance to be running and reachable through SSH.
  - Copy this new instance's hostname for later
6. Update the `artifacts/inventory.yml`:
  - move to the `terraform-base` directory
  - run `terraform apply`, this should update the inventory file with actual instance-pool members properties.
7. Initialize TLS for the new instance:
  - move to this repository's root directory
  - run `ansible-playbook -i artifacts/inventory.yml ansible-playbooks/vault-cluster-tls-bootstrap.yaml -l <hostname-from-step-5>`
8. Unseal the new instance:
  - move to this repository's root directory
  - run `ansible-playbook -i artifacts/inventory.yml ansible-playbooks/vault-cluster-unseal.yaml -l <hostname-from-step-5>`
9. Wait for new cluster peer becomes a voter (can be checked from another node, running `vault operator raft list-peers`):
    ```bash
    vault operator raft list-peers
    # 【output】
    # Node                              Address               State       Voter
    # ----                              -------               -----       -----
    # paas-staging-vault-addab-jcseq    89.145.161.97:8201    leader      true
    # paas-staging-vault-addab-jppqr    89.145.162.86:8201    follower    true
    # paas-staging-vault-addab-slqku    89.145.163.92:8201    follower    true
    ```
10. If the instance you removed in step 4 is still present in the list, remove it from the cluster, running `vault operator raft remove-peer <hostname-from-step-4>`.
    ```bash
    vault operator raft remove-peer paas-staging-vault-addab-jppqr
    # 【output】
    # Peer removed successfully!
    ```
11. Repeat operations from step 4 for other cluster members found in step 3.
12. Once the cluster is fully updated, enable TLS renewal from vault-agent:
  - move to this repository's root directory
  - run `ansible-playbook -i artifacts/inventory.yml ansible-playbooks/vault-cluster-tls-agent.yaml`
13. Delete the older template (value before the step 2 update) as it's not used anymore:
    ```bash
    exo compute template delete -z de-fra-1 212a49ca-9951-4f84-9609-800aafe5c0b5
    # 【output】
    # [+] Are you sure you want to delete template 212a49ca-9951-4f84-9609-800aafe5c0b5 ("Kubernetes 1.24.1 control plane")? [yN]: y
    #  ✔ Deleting template 212a49ca-9951-4f84-9609-800aafe5c0b5... 3s
    ```
