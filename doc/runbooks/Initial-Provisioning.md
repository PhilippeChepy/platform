# Initial provisioning

## Build instances templates using Packer

- Move to the `packer` directory.
- Create a `vars.hcl` file (template: `vars.hcl.example`), this file should contains your Exoscale API key/secret.
- Initialize packer if you don't have the Exoscale Packer plugin (`packer init exoscale-vault.pkr.hcl`). Packer requires the same plugin for building each templates.
- Build each template (`packer build -var-file vars.hcl <packer-file>), and take note of template IDs that will be used for the provisioning with Terraform:
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

## Provision the infrastructure using Terraform

- Create a `locals.tf` file (template: `locals.tf.example`) at the root of this repository.
- Export your Exoscale credentials as environment variables:
    ```bash
    export EXOSCALE_API_KEY="EXOxxxxxxxxxxxxxxxxxxxxxxxx"
    export EXOSCALE_API_SECRET="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ```
- Create the base infrastructure:
    - Terraform: from the `terraform-base` sub-directory, run `terraform init` and `terraform apply`.
    - Ansible: from the **root directory**, run `ansible-playbook -i artifacts/vault-inventory.yml ansible-playbooks/vault-cluster-bootstrap.yaml`
- Configure the base infrastructure & Exoscale IAM Keys:
    - Terraform: from the `terraform-base-configuration` sub-directory, run `terraform init` and `terraform apply`.
    - Ansible: from the **root directory**, run `ansible-playbook -i artifacts/vault-inventory.yml ansible-playbooks/vault-cluster-tls-agent.yaml`
- Create the Kubernetes infrastructure:
    - Terraform: from the `terraform-kubernetes` sub-directory, run `terraform init` and `terraform apply`.
- Provision required deployments:
    - Terraform: from the `terraform-kubernetes-deployments-bootstrap` sub-directory, run `terraform init` and `terraform apply`.
- Provision core deployments & ingress-related deployments:
    - Terraform: from the `terraform-kubernetes-deployments-core` sub-directory, run `terraform init` and `terraform apply`.

Optionnally, if you want to integrate the infrastructure with Cloudflare, you can also apply the
`terraform-cloudflare` configuration.

### User namespaces

This platform tenancy model is a "Namespace as a service" model. This means isolation is made on a namespace level, using role bindings, resource limits/quotas, and network policies.

Assisted namespace management can be made through the `terraform-kubernetes-app-namespaces` sub-directory.
From there you can run `terraform init` then `terraform apply` to provision namespaces according to definitions found in the `locals.tf` file.
