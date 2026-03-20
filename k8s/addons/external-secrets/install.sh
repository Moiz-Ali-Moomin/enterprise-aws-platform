#!/usr/bin/env bash
# ============================================================
# Install External Secrets Operator + ClusterSecretStore
#
# Prerequisites:
#   1. kubectl configured to target the correct EKS cluster
#   2. Helm v3 installed
#   3. IRSA role ARN from terraform output -raw external_secrets_role_arn
#
# This script is idempotent: re-running upgrades the release.
# ============================================================
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────
AWS_REGION="${AWS_REGION}"
IRSA_ROLE_ARN="${EXTERNAL_SECRETS_IRSA_ROLE_ARN}"
CHART_VERSION="0.10.3"   # Pin for reproducibility
# ── End Configuration ──────────────────────────────────────────

echo "==> Adding external-secrets Helm repository"
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

echo "==> Installing External Secrets Operator (chart ${CHART_VERSION})"
helm upgrade --install \
  external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version "${CHART_VERSION}" \
  --values "$(dirname "$0")/values.yaml" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${IRSA_ROLE_ARN}" \
  --wait \
  --timeout 5m

echo "==> Waiting for ESO webhook to be ready"
kubectl rollout status deployment/external-secrets-webhook \
  --namespace external-secrets \
  --timeout=120s

echo "==> Applying ClusterSecretStore (AWS Secrets Manager backend)"
# Substitute AWS_REGION in the ClusterSecretStore manifest
sed "s/\${AWS_REGION}/${AWS_REGION}/g" \
  "$(dirname "$0")/cluster-secret-store.yaml" \
  | kubectl apply -f -

echo "==> Verifying ClusterSecretStore"
kubectl get clustersecretstore aws-secrets-manager

echo "==> External Secrets Operator installed successfully"
echo "    To verify: kubectl get externalsecrets -A"
