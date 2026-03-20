#!/usr/bin/env bash
# ============================================================
# Install AWS Load Balancer Controller
#
# Prerequisites:
#   1. kubectl configured to target the correct EKS cluster
#   2. Helm v3 installed
#   3. Values substituted (EKS_CLUSTER_NAME, AWS_REGION, etc.)
#   4. terraform output -raw alb_controller_role_arn captured
#
# This script is idempotent: re-running upgrades the release.
# ============================================================
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────
CLUSTER_NAME="${EKS_CLUSTER_NAME}"
AWS_REGION="${AWS_REGION}"
VPC_ID="${VPC_ID}"
IRSA_ROLE_ARN="${ALB_CONTROLLER_IRSA_ROLE_ARN}"
CHART_VERSION="1.8.1"   # Pin chart version for reproducibility
# ── End Configuration ──────────────────────────────────────────

echo "==> Adding eks-charts Helm repository"
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "==> Installing AWS Load Balancer Controller (chart ${CHART_VERSION})"
helm upgrade --install \
  aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "$(dirname "$0")/values.yaml" \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${IRSA_ROLE_ARN}" \
  --wait \
  --timeout 5m

echo "==> Verifying deployment"
kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout=120s

echo "==> ALB Controller installed successfully"
echo "    Check IngressClass: kubectl get ingressclass alb"
