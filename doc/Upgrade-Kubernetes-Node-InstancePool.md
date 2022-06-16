# Kubernetes node instance-pools upgrade procedure

1. Build the new Kubernetes node template:
    - move to the `packer` directory
    - run packer: `packer build -var-file vars.hcl exoscale-kube-node.pkr.hcl`
    - grab the template ID from the output: `--> exoscale.base: Kubernetes 1.24.1 node @ de-fra-1 (fee05f1e-28f5-42df-a3a6-0f4ddd542b80)`
2. Update the Kubernetes node instance-pool:
    - Update the value for `platform_components.kubernetes.templates.kubelet` in your `locals.tf` file with the template ID from step 1. Keep the older value for the cleanup step
    - move to the `terraform-kubernetes` directory
    - run `terraform apply`, this should update each node instance-pool template ID
3. List nodes to upgrade:
    - Move to the `artifacts` directory
    - Run `export KUBECONFIG=./admin.kubeconfig`
    - Run `kubectl get nodes`
    ```bash
    kubectl get nodes
    # 【output】
    # NAME                                        STATUS   ROLES    AGE   VERSION
    # paas-staging-general-012d4-kdlvx            Ready    <none>   13d   v1.24.1
    # paas-staging-general-012d4-knhgn            Ready    <none>   13d   v1.24.1
    # paas-staging-ingress-default-4bdd4-rbicn    Ready    <none>   13d   v1.24.1
    # paas-staging-ingress-internal-23596-ajqcq   Ready    <none>   10d   v1.24.1
    ```
4. Drain a node, to orchestrate its hosted workload on another one:
    ```bash
    kubectl drain paas-staging-general-012d4-kdlvx --ignore-daemonsets
    # 【output】
    # node/paas-staging-general-012d4-kdlvx already cordoned
    # WARNING: ignoring DaemonSet-managed Pods: kube-system/cilium-fngs9
    # evicting pod vault-agent-injector/vault-agent-injector-f94b96967-m5nwx
    # evicting pod kube-system/konnectivity-agent-5649884967-6gjpq
    # evicting pod ingress-nginx-default/ingress-nginx-admission-patch-pqm2r
    # evicting pod cert-manager/cert-manager-cainjector-5f6fd79648-qmpk5
    # evicting pod reloader/reloader-f877dcc64-kskhp
    # evicting pod kube-system/coredns-678bbdfc47-hs6lj
    # evicting pod ingress-nginx-internal/external-dns-85797b897f-zgk45
    # evicting pod kube-system/metrics-server-648f457f4f-z8qs9
    # evicting pod ingress-nginx-internal/ingress-nginx-admission-patch-qjhmw
    # pod/ingress-nginx-admission-patch-pqm2r evicted
    # pod/ingress-nginx-admission-patch-qjhmw evicted
    # pod/external-dns-85797b897f-zgk45 evicted
    # pod/cert-manager-cainjector-5f6fd79648-qmpk5 evicted
    # pod/metrics-server-648f457f4f-z8qs9 evicted
    # pod/reloader-f877dcc64-kskhp evicted
    # pod/konnectivity-agent-5649884967-6gjpq evicted
    # pod/vault-agent-injector-f94b96967-m5nwx evicted
    # pod/coredns-678bbdfc47-hs6lj evicted
    # node/paas-staging-general-012d4-kdlvx evicted
    ```
5. With `exo` CLI, or by other means, delete the related instance (instance name is exactly the same as the node name)
    ```bash
    exo compute instance delete paas-staging-general-012d4-kdlvx
    # 【output】
    # [+] Are you sure you want to delete instance "paas-staging-general-012d4-kdlvx"? [yN]: y
    #  ✔ Deleting instance "paas-staging-general-012d4-kdlvx"... 12s
    ```
6. A new instance will be automatically created to replace the one you just deleted. Wait for a new node to appear.
    The new node must be in `Ready` status, and the related CSRs approved (by cloud controller manager):
    ```bash
    kubectl get nodes,csr 
    # NAME                                             STATUS   ROLES    AGE   VERSION
    # node/paas-staging-general-012d4-aigxl            Ready    <none>   34s   v1.24.1
    # node/paas-staging-general-012d4-bugfj            Ready    <none>   88s   v1.24.1
    # node/paas-staging-general-012d4-knhgn            Ready    <none>   13d   v1.24.1
    # node/paas-staging-ingress-default-4bdd4-rbicn    Ready    <none>   13d   v1.24.1
    # node/paas-staging-ingress-internal-23596-ajqcq   Ready    <none>   10d   v1.24.1
    #
    # NAME                                                                                                 AGE   SIGNERNAME                                    REQUESTOR                                      REQUESTEDDURATION   CONDITION
    # certificatesigningrequest.certificates.k8s.io/csr-56tms                                              87s   kubernetes.io/kubelet-serving                 system:node:paas-staging-general-012d4-bugfj   <none>              Approved,Issued
    # certificatesigningrequest.certificates.k8s.io/csr-cfqst                                              33s   kubernetes.io/kubelet-serving                 system:node:paas-staging-general-012d4-aigxl   <none>              Approved,Issued
    # certificatesigningrequest.certificates.k8s.io/node-csr--12jWovspWiKeOCVDEK5cZ2sYRP5yx3JMZ3x4V3uxbM   34s   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:44x74t                        <none>              Approved,Issued
    # certificatesigningrequest.certificates.k8s.io/node-csr-kHmpsjs8yGRGaRQ1jZidJN2JGTFVT4RF9sgtre-OGQQ   88s   kubernetes.io/kube-apiserver-client-kubelet   system:bootstrap:44x74t                        <none>              Approved,Issued
    ```
7. Repeat operations from step 4 for other nodes found in step 3.
8. Delete the older template (value before the step 2 update) as it's not used anymore:
    ```bash
    exo compute template delete -z de-fra-1 ec9b5fd9-bc18-496e-9daa-64e9dbde6fe1
    # 【output】
    # [+] Are you sure you want to delete template ec9b5fd9-bc18-496e-9daa-64e9dbde6fe1 ("Kubernetes 1.24.1 node")? [yN]: y
    #  ✔ Deleting template ec9b5fd9-bc18-496e-9daa-64e9dbde6fe1... 3s
    ```
