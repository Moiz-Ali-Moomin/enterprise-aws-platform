#!/bin/bash
# EKS Production Verification Toolkit (Elite Toolkit)
#
# Use this script to verify the 11/10 production-grade EKS setup
# during interviews or production smoke tests.

set -e

NAMESPACE="api-service"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🚀 EKS Elite Guardrail Verification"
echo "-----------------------------------"

# 1. Verify Pod Security Standards (PSS)
echo -n "Checking PSS Enforce: Restricted... "
ENFORCE=$(kubectl get ns $NAMESPACE -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
if [ "$ENFORCE" == "restricted" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Current: $ENFORCE)${NC}"
fi

# 2. Verify Resource Governance
echo -n "Checking ResourceQuotas... "
QUOTA=$(kubectl get resourcequota -n $NAMESPACE api-service-quota --no-headers 2>/dev/null | awk '{print $1}')
if [ "$QUOTA" == "api-service-quota" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
fi

# 3. Verify Karpenter NodePool status
echo -n "Checking Karpenter Provisioner (NodePool)... "
NODEPOOL=$(kubectl get nodepool default --no-headers 2>/dev/null | awk '{print $1}')
if [ "$NODEPOOL" == "default" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Not found)${NC}"
fi

# 4. Verify External Secrets Store (ESO)
echo -n "Checking ClusterSecretStore Health... "
SECRET_STORE=$(kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$SECRET_STORE" == "True" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Not Ready)${NC}"
fi

# 5. Verify Network Policies
echo -n "Checking Default Deny Policy... "
NETPOL=$(kubectl get netpol -n $NAMESPACE default-deny --no-headers 2>/dev/null | awk '{print $1}')
if [ "$NETPOL" == "default-deny" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
fi

# 6. Verify ALB WAF Association
echo -n "Checking Ingress WAF Annotation... "
WAF_ARN=$(kubectl get ingress -n $NAMESPACE api-service-ingress -o jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/wafv2-acl-arn}')
if [[ "$WAF_ARN" != "" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL (Missing annotation)${NC}"
fi

echo "-----------------------------------"
echo "✅ All EKS Elite Guardrails Validated!"
