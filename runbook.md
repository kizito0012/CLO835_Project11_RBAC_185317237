# CLO835 Project 11 Operations Runbook

**Student:** Christian Onwuanaku  
**Student ID:** 185317237  
**Cluster:** clo835-rbac-185317237  
**Namespace:** rbac-185317237  
**Docker Hub Image:** christian9299/clo835-app:v1  

---

## 1. Purpose

This runbook explains how to start, test, operate, troubleshoot, and recover the CLO835 Project 11 Kubernetes RBAC environment.

The project uses three least-privilege personas:

- **Deployer** – manages approved application resources.
- **Readonly** – views selected resources but cannot read Secrets or modify resources.
- **CI** – gets and patches Deployments so it can update the application image.

Each persona has its own ServiceAccount, Role, RoleBinding, and kubeconfig.

---

## 2. Project variables

```bash
SID=185317237
NAMESPACE=rbac-185317237
CLUSTER=clo835-rbac-185317237
IMAGE=christian9299/clo835-app:v1
```

---

## 3. Environment checks

Run these commands before bootstrap:

```bash
docker version
kind version
kubectl version --client
git --version
```

Confirm Docker Desktop is running.

Check the current Kubernetes context:

```bash
kubectl config current-context
```

The expected project context is:

```text
kind-clo835-rbac-185317237
```

Switch to it when necessary:

```bash
kubectl config use-context kind-clo835-rbac-185317237
```

---

## 4. Clean bootstrap

From the repository root:

```bash
./bootstrap.sh
```

The script should:

1. Create a kind cluster with one control-plane and one worker.
2. Create namespace `rbac-185317237`.
3. Apply RBAC manifests.
4. Apply workload manifests.
5. Generate kubeconfigs for deployer, readonly, and CI.
6. Run the RBAC permission test suite.

Healthy output should end with:

```text
Total checks: 35
Passed: 35
Failed: 0
Bootstrap completed successfully
```

Check cluster health:

```bash
kubectl get nodes
```

Expected:

```text
clo835-rbac-185317237-control-plane   Ready
clo835-rbac-185317237-worker          Ready
```

Check project resources:

```bash
kubectl get all,sa,role,rolebinding -n rbac-185317237
```

Expected resources include:

```text
deployment/web-185317237
service/web-185317237

serviceaccount/deployer-185317237
serviceaccount/readonly-185317237
serviceaccount/ci-185317237

role/deployer-role-185317237
role/readonly-role-185317237
role/ci-role-185317237

rolebinding/deployer-binding-185317237
rolebinding/readonly-binding-185317237
rolebinding/ci-binding-185317237
```

---

## 5. Verify student ID in the ConfigMap

```bash
kubectl get configmap app-config-185317237 \
  -n rbac-185317237 \
  -o yaml
```

Expected:

```yaml
data:
  owner: "185317237"
```

---

## 6. Run the RBAC permission tests

```bash
./tests/rbac-test.sh
```

Healthy summary:

```text
Total checks: 35
Passed: 35
Failed: 0
```

Check the exit code:

```bash
echo $?
```

Expected:

```text
0
```

A PASS line means the actual permission matched the expected result.

Example allowed check:

```text
PASS: persona=readonly verb=list resource=pods expected=yes actual=yes
```

Example denied check:

```text
PASS: persona=readonly verb=get resource=secrets expected=no actual=no
```

A FAIL line means the actual result did not match the expected result.

---

## 7. Deployer persona

The deployer can manage approved workload resources in `rbac-185317237`.

### Scale the Deployment to three replicas

```bash
kubectl \
  --kubeconfig kubeconfigs/deployer.kubeconfig \
  scale deployment/web-185317237 \
  --replicas=3 \
  -n rbac-185317237
```

Verify:

```bash
kubectl \
  --kubeconfig kubeconfigs/deployer.kubeconfig \
  get deployment web-185317237 \
  -n rbac-185317237
```

Expected:

```text
READY   UP-TO-DATE   AVAILABLE
3/3     3            3
```

Check rollout status:

```bash
kubectl \
  --kubeconfig kubeconfigs/deployer.kubeconfig \
  rollout status deployment/web-185317237 \
  -n rbac-185317237
```

### Show Secret denial

```bash
kubectl \
  --kubeconfig kubeconfigs/deployer.kubeconfig \
  get secret db-creds-185317237 \
  -n rbac-185317237
```

Expected:

```text
Error from server (Forbidden)
```

### Show RBAC denial

```bash
kubectl \
  --kubeconfig kubeconfigs/deployer.kubeconfig \
  auth can-i create rolebindings \
  -n rbac-185317237
```

Expected:

```text
no
```

### Return to two replicas

```bash
kubectl \
  --kubeconfig kubeconfigs/deployer.kubeconfig \
  scale deployment/web-185317237 \
  --replicas=2 \
  -n rbac-185317237
```

---

## 8. Readonly persona

The readonly persona can inspect selected resources but cannot modify them or read Secrets.

### List pods

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  get pods \
  -n rbac-185317237
```

### Describe the Deployment

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  describe deployment web-185317237 \
  -n rbac-185317237
```

### List Services

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  get services \
  -n rbac-185317237
```

### List ConfigMaps

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  get configmaps \
  -n rbac-185317237
```

### Show Secret denial

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  get secret db-creds-185317237 \
  -n rbac-185317237
```

Expected:

```text
Error from server (Forbidden)
```

### Show modification denial

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  auth can-i create configmaps \
  -n rbac-185317237
```

Expected:

```text
no
```

---

## 9. CI persona

The CI persona can only get and patch Deployments.

### Update the application image

```bash
kubectl \
  --kubeconfig kubeconfigs/ci.kubeconfig \
  set image deployment/web-185317237 \
  web=christian9299/clo835-app:v1 \
  -n rbac-185317237
```

Expected:

```text
deployment.apps/web-185317237 image updated
```

### Verify the image

```bash
kubectl \
  --kubeconfig kubeconfigs/ci.kubeconfig \
  get deployment web-185317237 \
  -n rbac-185317237 \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Expected:

```text
christian9299/clo835-app:v1
```

### Show pod-list denial

```bash
kubectl \
  --kubeconfig kubeconfigs/ci.kubeconfig \
  get pods \
  -n rbac-185317237
```

Expected:

```text
Error from server (Forbidden)
```

### Show logs denial

```bash
kubectl \
  --kubeconfig kubeconfigs/ci.kubeconfig \
  logs deployment/web-185317237 \
  -n rbac-185317237
```

Expected:

```text
Error from server (Forbidden)
```

### Show delete denial

```bash
kubectl \
  --kubeconfig kubeconfigs/ci.kubeconfig \
  auth can-i delete deployments.apps \
  -n rbac-185317237
```

Expected:

```text
no
```

---

## 10. Diagnose an authorization failure

Run the test suite:

```bash
./tests/rbac-test.sh
```

Identify the affected persona from the FAIL lines.

Use the affected persona's kubeconfig.

Example for readonly:

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  auth can-i --list \
  -n rbac-185317237
```

Test individual verbs:

```bash
kubectl --kubeconfig kubeconfigs/readonly.kubeconfig \
  auth can-i get pods -n rbac-185317237

kubectl --kubeconfig kubeconfigs/readonly.kubeconfig \
  auth can-i list pods -n rbac-185317237

kubectl --kubeconfig kubeconfigs/readonly.kubeconfig \
  auth can-i watch pods -n rbac-185317237
```

Interpret the results:

```text
Only one permission is missing:
The Role was probably edited.

All expected permissions are missing:
The RoleBinding path is probably broken.
Possible causes:
- deleted RoleBinding
- wrong ServiceAccount subject
- binding in the wrong namespace
```

Before entering break-glass, state the predicted fault.

Example:

```text
Readonly still has get and watch, but list is missing.
I predict that the list verb was removed from readonly-role-185317237.
```

---

## 11. Break-glass policy

Break-glass access is used only after a normal persona has a confirmed authorization problem.

It gives temporary administrator access so that damaged Roles and RoleBindings can be inspected and repaired.

Normal personas must never receive cluster-admin because they could read Secrets, change RBAC, affect other namespaces, and increase their own permissions.

Administrator access must be exited immediately after recovery.

Enter break-glass:

```bash
./break-glass.sh
```

---

## 12. Inspect the RBAC fault

Inspect in this order:

1. Does the RoleBinding exist?
2. Is the subject ServiceAccount name correct?
3. Is the subject namespace correct?
4. Is `roleRef` correct?
5. Are the Role verbs and resources correct?

### Check where bindings exist

```bash
kubectl get rolebinding -A | grep 185317237
```

### Check the readonly binding

```bash
kubectl get rolebinding readonly-binding-185317237 \
  -n rbac-185317237
```

A `NotFound` error means it was deleted.

### Inspect the binding YAML

```bash
kubectl get rolebinding readonly-binding-185317237 \
  -n rbac-185317237 \
  -o yaml
```

Correct subject:

```yaml
subjects:
  - kind: ServiceAccount
    name: readonly-185317237
    namespace: rbac-185317237
```

Correct role reference:

```yaml
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: readonly-role-185317237
```

### Inspect the Role

```bash
kubectl get role readonly-role-185317237 \
  -n rbac-185317237 \
  -o yaml
```

Readonly should contain:

```yaml
verbs:
  - get
  - list
  - watch
```

When another persona is affected, use:

```text
deployer-binding-185317237
deployer-role-185317237

ci-binding-185317237
ci-role-185317237
```

---

## 13. Repair RBAC

Inside break-glass:

```bash
./bootstrap.sh --repair-rbac
```

This reapplies the canonical RBAC YAML from `manifests/rbac/`.

Exit break-glass:

```bash
exit
```

Prove recovery:

```bash
./tests/rbac-test.sh
```

Expected:

```text
Total checks: 35
Passed: 35
Failed: 0
```

---

## 14. Deleted RoleBinding practice

Create the fault:

```bash
kubectl delete rolebinding readonly-binding-185317237 \
  -n rbac-185317237
```

Run tests:

```bash
./tests/rbac-test.sh
```

Check the symptom:

```bash
kubectl \
  --kubeconfig kubeconfigs/readonly.kubeconfig \
  auth can-i list pods \
  -n rbac-185317237
```

Expected:

```text
no
```

State:

```text
Readonly lost its normal permissions.
I predict that readonly-binding-185317237 was deleted.
```

Enter break-glass:

```bash
./break-glass.sh
```

Confirm:

```bash
kubectl get rolebinding readonly-binding-185317237 \
  -n rbac-185317237
```

Expected:

```text
Error from server (NotFound)
```

Repair:

```bash
./bootstrap.sh --repair-rbac
```

Exit:

```bash
exit
```

Verify:

```bash
./tests/rbac-test.sh
```

Expected:

```text
Passed: 35
Failed: 0
```

---

## 15. Regenerate expired kubeconfigs

Persona tokens are temporary.

If tests show blank `actual=` values or credential errors, run:

```bash
./bootstrap.sh --regenerate-kubeconfigs
```

Then:

```bash
./tests/rbac-test.sh
```

Expected:

```text
Passed: 35
Failed: 0
```

Confirm generated kubeconfigs are not tracked:

```bash
git ls-files kubeconfigs/
```

Expected:

```text
kubeconfigs/.gitkeep
```

---

## 16. Presentation readiness checks

Run shortly before presenting:

```bash
git status
git log -1 --format="%H"
kubectl get nodes
kubectl get deployment web-185317237 -n rbac-185317237
./tests/rbac-test.sh
```

Expected:

```text
nothing to commit, working tree clean
Both nodes Ready
Deployment 2/2 Ready
Passed: 35
Failed: 0
```

---

## 17. Final repository

```text
https://github.com/kizito0012/CLO835_Project11_RBAC_185317237
```
