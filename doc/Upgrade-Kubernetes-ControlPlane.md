# Kubernetes control plane upgrade procedure

1. Build the new Kubernetes control plane template:
  - move to the `packer` directory
  - run packer: `packer build -var-file vars.hcl exoscale-kube-controlplane.pkr.hcl`
  - grab the template ID from the output: `--> exoscale.base: Kubernetes 1.24.1 control plane @ de-fra-1 (b8f9c7ea-054f-45d6-951e-c6d921dafb0c)`
2. Update the Kubernetes control plane instance-pool:
  - Update the value for `platform_components.kubernetes.templates.control_plane` in your `locals.tf` file with the template ID from step 1. Keep the older
  value for the cleanup step
  - move to the `terraform-kubernetes` directory
  - run `terraform apply`, this should update the instance-pool template ID
3. With `exo` CLI, or by other means, get the list of current instances. These instances are using the old template:
    ```bash  
    exo compute instance list |grep kube
    # 【output】
    # | e7678152-d7a5-4b0e-9a5e-65665b9bebee | paas-staging-kubernetes-4976a-iznkw       | de-fra-1 | standard.tiny  | 89.145.161.16   | running |
    # | 0e30ea46-477c-4025-8044-e20c09c9caa6 | paas-staging-kubernetes-4976a-imfbp       | de-fra-1 | standard.tiny  | 89.145.161.6    | running |
    ```
4. Stop the API-server service on an instance:
    - Move to the `artifacts` directory
    - Connect to the instance (`ssh -i id_ed25519 ubuntu@89.145.161.16`)
    - Stop the kube-vault-agent service (`sudo systemctl stop kube-vault-agent`)
    - Stop the kube-apiserver service (`sudo systemctl stop kube-apiserver`)
    - Disconnect (`exit` or `logout`)
5. Ensure the apiserver traffic is now handled by another node:
    - Move to the `artifacts` directory
    - Run `export KUBECONFIG=./admin.kubeconfig`
    - Run `kubectl get nodes` until there is no errors (should be less than 10s after starting to stop the kube-apiserver service)
6. With `exo` CLI, or by other means, delete the instance.
    ```bash
    exo compute instance delete paas-staging-kubernetes-4976a-iznkw
    # 【output】
    # [+] Are you sure you want to delete instance "paas-staging-kubernetes-4976a-iznkw"? [yN]: y
    #  ✔ Deleting instance "paas-staging-kubernetes-4976a-iznkw"... 12s
    ```
7. A new instance will be automatically created to replace the one you just deleted:
    - Wait for the new instance to be running and reachable through SSH.
    - Copy this new instance's hostname for later
8. Connect to the instance and ensure every services are running correctly, in particular:
    - `kube-scheduler.service`
    - `exoscale-cloud-controller-manager.service`
    - `kube-apiserver.service`
    - `kube-controller-manager.service`
    - `kube-vault-agent.service`
    - `cluster-autoscaler.service`
    - `konnectivity.service`
9. Repeat operations from step 4 for other cluster members found in step 3.
10. Delete the older template (value before the step 2 update) as it's not used anymore:
    ```bash
    exo compute template delete -z de-fra-1 f229708b-ce5f-4cd4-a9fa-bd96c89c1a49
    # 【output】
    # [+] Are you sure you want to delete template f229708b-ce5f-4cd4-a9fa-bd96c89c1a49 ("Kubernetes 1.24.1 control plane")? [yN]: y
    # ✔ Deleting template f229708b-ce5f-4cd4-a9fa-bd96c89c1a49... 3s
    ```

## Additional step: Update the Konnectivity agent deployment

At least one instance of Konnectivity agent needs to connect directly to a Konnectivity server which is hosted on each control-plane node.
This means once you remove a control plane node, Konnectivity agent cannot connect anymore to it.
To solve this issue, you have to go to the `terraform-kubernetes-deployments-bootstrap` directory and run `terraform apply` again, in order
to refresh the konnectivity agent deployment.