# EKS Troubleshooting Runbook

This runbook covers common production issues for the EKS compute platform.

## 1. Karpenter Node Provisioning Failures

If pods are stuck in `Pending` and Karpenter is not launching nodes:

### Symptoms
- Pod state: `Pending`
- Pod event: `FailedScheduling` (no nodes available)
- Karpenter logs: `Controller.Provisioning` errors

### Checks
1.  **Check Karpenter Logs**:
    ```bash
    kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller
    ```
2.  **Verify EC2NodeClass Tag Selectors**:
    Ensure the tags in `k8s/addons/karpenter/ec2nodeclass.yaml` match the tags on your subnets and security groups.
3.  **Check IRSA Permissions**:
    Verify the Karpenter IAM role has `ec2:RunInstances` and `iam:PassRole`.
4.  **Resource Limits**:
    Check if the `NodePool` `spec.limits` has been reached.

---

## 2. Pod Communication Issues (NetworkPolicies)

If pods are failing to connect to RDS or external APIs:

### Symptoms
- `Connection timeout` in application logs
- `Temporary failure in name resolution`

### Checks
1.  **Verify CoreDNS**:
    Ensure `kube-system` CoreDNS pods are running.
2.  **Check NetworkPolicy Egress**:
    Ensure `k8s/api-service/network-policy.yaml` allows traffic to the target CIDR/port.
3.  **Verify VPC CNI Policy Enforcement**:
    Ensure the VPC CNI addon has `networkPolicy.enabled: true`.
    ```bash
    aws eks describe-addon --cluster-name <name> --addon-name vpc-cni
    ```

---

## 3. Secrets Sync Failures (ESO)

If pods fail to start because a secret is missing:

### Symptoms
- Pod event: `Warning FailedMount` (secret "api-service-secrets" not found)

### Checks
1.  **Check ExternalSecret Status**:
    ```bash
    kubectl get externalsecret -n api-service api-service-secrets
    ```
2.  **Check ClusterSecretStore Health**:
    ```bash
    kubectl get clustersecretstore
    ```
3.  **Verify ESO IRSA**:
    Ensure the `external-secrets` IAM role has access to the specific Secrets Manager ARN.

---

## 4. ALB Ingress Readiness

If the ALB is not forwarding traffic or returns 502/504:

### Symptoms
- `curl` returns 502 Bad Gateway
- ALB Target Group shows `Unhealthy` targets

### Checks
1.  **Check Ingress Events**:
    ```bash
    kubectl describe ingress -n api-service api-service-ingress
    ```
2.  **ALB Controller Logs**:
    ```bash
    kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
    ```
3.  **Target Type**:
    Ensure `alb.ingress.kubernetes.io/target-type: ip` is set (required for Fargate or direct pod routing).
4.  **Security Groups**:
    Ensure the node security group allows ingress from the ALB on port 8000.
