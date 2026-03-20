#!/usr/bin/env bash
# ============================================================
# Install Karpenter
#
# Prerequisites:
#   1. kubectl configured to target the correct EKS cluster
#   2. Helm v3 installed
#   3. Terraform outputs captured (see Configuration below)
#   4. Managed node group exists (Karpenter needs a node to
#      schedule its own pods on before it can launch more nodes)
#
# Run AFTER the EKS cluster and managed node group exist.
# This script is idempotent: re-running upgrades the release.
# ============================================================
set -euo pipefail

# ── Configuration (substitute from terraform output) ───────
CLUSTER_NAME="${EKS_CLUSTER_NAME}"
CLUSTER_ENDPOINT="${EKS_CLUSTER_ENDPOINT}"
KARPENTER_IRSA_ROLE_ARN="${KARPENTER_IRSA_ROLE_ARN}"
INTERRUPTION_QUEUE_NAME="${KARPENTER_INTERRUPTION_QUEUE_NAME}"
AWS_REGION="${AWS_REGION}"
CHART_VERSION="1.0.6"  # Pin for reproducibility — check https://github.com/aws/karpenter-provider-aws/releases
# ── End Configuration ────────────────────────────────────────

echo "==> Adding Karpenter Helm repository (ECR public)"
# Karpenter chart is hosted on ECR public (not on Artifact Hub)
helm repo add karpenter https://charts.karpenter.sh
helm repo update

echo "==> Creating karpenter namespace"
kubectl create namespace karpenter --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Karpenter CRDs (required before chart install)"
# CRDs must be installed before the chart or the webhook validation will fail
kubectl apply -f https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${CHART_VERSION}/pkg/apis/crds/karpenter.sh_nodepools.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${CHART_VERSION}/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${CHART_VERSION}/pkg/apis/crds/karpenter.sh_nodeclaims.yaml

echo "==> Installing Karpenter via Helm (chart ${CHART_VERSION})"
helm upgrade --install \
  karpenter \
  karpenter/karpenter \
  --namespace karpenter \
  --version "${CHART_VERSION}" \
  --values "$(dirname "$0")/values.yaml" \
  --set settings.clusterName="${CLUSTER_NAME}" \
  --set settings.clusterEndpoint="${CLUSTER_ENDPOINT}" \
  --set settings.interruptionQueueName="${INTERRUPTION_QUEUE_NAME}" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${KARPENTER_IRSA_ROLE_ARN}" \
  --wait \
  --timeout 5m

echo "==> Waiting for Karpenter to be ready"
kubectl rollout status deployment/karpenter \
  --namespace karpenter \
  --timeout=120s

echo "==> Applying EC2NodeClass (defines what nodes to launch)"
sed \
  -e "s/\${AWS_REGION}/${AWS_REGION}/g" \
  -e "s/\${EKS_CLUSTER_NAME}/${CLUSTER_NAME}/g" \
  "$(dirname "$0")/ec2nodeclass.yaml" \
  | kubectl apply -f -

echo "==> Applying NodePool (defines scheduling constraints)"
kubectl apply -f "$(dirname "$0")/nodepool.yaml"

echo "==> Karpenter installed successfully"
echo "    Check NodePools:    kubectl get nodepools"
echo "    Check EC2NodeClass: kubectl get ec2nodeclasses"
echo "    Watch node launch:  kubectl get nodes -w"
