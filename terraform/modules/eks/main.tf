############################################
# Data Sources
############################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Fetch the TLS certificate thumbprint for the EKS OIDC endpoint.
# This is required when creating aws_iam_openid_connect_provider.
# AWS validates OIDC tokens using this thumbprint.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

############################################
# KMS — EKS Secrets Envelope Encryption
#
# Encrypts Kubernetes Secrets at rest in etcd
# using a customer-managed KMS key.
# This means even AWS cannot read your K8s
# Secrets without access to this KMS key.
############################################

resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secrets encryption - ${var.project_name}-${var.environment}"
  deletion_window_in_days = 14
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEKSService"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-secrets-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project_name}-${var.environment}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

############################################
# CloudWatch Log Group — EKS Control Plane
#
# EKS control plane logs (API server, audit,
# authenticator, scheduler, controller manager)
# are invaluable for security auditing and
# debugging cluster-level issues.
#
# Log group name MUST follow the format:
# /aws/eks/<cluster-name>/cluster
# or EKS won't send logs here.
############################################

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.project_name}-${var.environment}-cluster/cluster"
  retention_in_days = var.cluster_log_retention_days
  kms_key_id        = aws_kms_key.eks_secrets.arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster-logs"
    Environment = var.environment
  }
}

############################################
# IAM — EKS Cluster Role
#
# The cluster control plane needs this role
# to make calls to AWS APIs on your behalf
# (describe VPCs, create ENIs, etc.)
############################################

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-cluster-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

############################################
# IAM — EKS Node Group Role
#
# Managed node group EC2 instances assume this
# role to call AWS APIs they need at runtime:
# ECR pulls, VPC CNI plugin, CloudWatch agent.
############################################

resource "aws_iam_role" "eks_node_group" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-node-role"
    Environment = var.environment
  }
}

# Required by the VPC CNI plugin (pod networking)
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Required for pod IP allocation via VPC CNI
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Required for EKS to pull images from ECR
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Required for CloudWatch Container Insights on EKS
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

############################################
# Security Group — Node-to-Control-Plane
#
# EKS creates its own cluster security group,
# but we add an explicit group to control
# node group egress and allow the ALB Controller
# webhook communication.
############################################

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-${var.environment}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Nodes need to talk to each other (pod-to-pod routing)
  ingress {
    description = "Allow all intra-node communication"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  # ALB Controller webhook runs on nodes; ALB needs to call it
  ingress {
    description = "ALB Controller webhook from control plane"
    protocol    = "tcp"
    from_port   = 9443
    to_port     = 9443
    cidr_blocks = [var.vpc_cidr]
  }

  # Nodes need full outbound for: ECR pulls, AWS APIs, internet (system updates)
  # VPC endpoints handle ECR/CloudWatch/SSM — actual internet egress is minimal
  egress {
    description = "Allow all outbound"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-nodes-sg"
    Environment = var.environment
    # Required tag for ALB controller to discover the SG
    "kubernetes.io/cluster/${var.project_name}-${var.environment}-cluster" = "owned"
  }
}

############################################
# EKS Cluster
#
# Private endpoint: API server is not reachable
# from the internet. kubectl access requires VPN
# or AWS SSM/bastion.
#
# Public endpoint: disabled in prod for security.
# Enable temporarily for initial cluster setup.
#
# Envelope encryption: Kubernetes Secrets stored
# in etcd are encrypted with our KMS key.
# Without this, Secrets are base64 only (not secure).
#
# Control plane logging: enabled for all components
# for security audit and debugging capability.
############################################

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    # Public endpoint enabled for initial bootstrapping convenience.
    # Set to false in production after initial setup.
    # Access then requires SSM/VPN to reach the private API endpoint.
    endpoint_public_access  = var.enable_public_endpoint
    security_group_ids      = [aws_security_group.eks_nodes.id]
  }

  # Encrypt Kubernetes Secrets at rest in etcd using our KMS CMK
  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  # Control plane logging — all log types captured for security audit
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Ensure the log group and IAM roles exist before cluster creation
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster"
    Environment = var.environment
  }
}

############################################
# EKS Managed Node Group
#
# Managed node groups: AWS handles:
#   - AMI updates (patching)
#   - Node draining on update
#   - EC2 instance lifecycle
#
# We use PRIVATE subnets only — nodes never
# get public IPs. ALB pods route through the
# load balancer's public subnets.
#
# Spot instances (optional): ~70% cheaper,
# Kubernetes drains gracefully on interruption.
# Stateless apps tolerate Spot well.
# Critical system pods (CoreDNS, ALB Controller)
# should use on-demand via nodeSelector/taint.
############################################

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types

  # Spot instances for cost savings.
  # capacity_type = "SPOT" makes ~70% cheaper but interruptible.
  # Use ON_DEMAND for prod baseline, SPOT for burst node group.
  capacity_type = var.enable_spot_nodes ? "SPOT" : "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Rolling update: replaces one node at a time.
  # max_unavailable = 1 ensures cluster has capacity during updates.
  update_config {
    max_unavailable = 1
  }

  labels = {
    environment = var.environment
    role        = "worker"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
    aws_iam_role_policy_attachment.cloudwatch_agent,
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-node-group"
    Environment = var.environment
    # Required for Cluster Autoscaler to manage this node group
    "k8s.io/cluster-autoscaler/enabled"                                      = "true"
    "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}-cluster" = "owned"
  }
}

############################################
# EKS OIDC Identity Provider
#
# This is the foundation of IRSA (IAM Roles
# for Service Accounts). It allows EKS to
# issue OIDC tokens that AWS STS can validate,
# granting Kubernetes pods IAM permissions
# WITHOUT any static credentials inside the pod.
#
# Flow:
#   Pod starts → kubelet injects projected volume
#   with a short-lived OIDC token bound to the pod's
#   ServiceAccount → SDK calls
#   STS:AssumeRoleWithWebIdentity → receives
#   temporary AWS credentials → API calls succeed
#
# This is the Kubernetes equivalent of GitHub
# Actions OIDC — same principle, different context.
############################################

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-oidc"
    Environment = var.environment
  }
}

############################################
# Local: OIDC provider URL without https://
# Used in IRSA trust policy condition keys
############################################

locals {
  oidc_issuer_host = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

############################################
# IRSA — AWS Load Balancer Controller
#
# The ALB Controller watches Kubernetes Ingress
# objects and creates/manages AWS ALBs.
# It needs EC2 and ELBv2 permissions to do so.
#
# Trust condition: only the ServiceAccount named
# "aws-load-balancer-controller" in the
# "kube-system" namespace can assume this role.
############################################

resource "aws_iam_role" "alb_controller" {
  name = "${var.project_name}-${var.environment}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_host}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-controller-role"
    Environment = var.environment
  }
}

# AWS-maintained policy document for the ALB Controller.
# Using the managed policy document from the upstream
# AWS Load Balancer Controller IAM policy JSON
# (https://github.com/kubernetes-sigs/aws-load-balancer-controller).
resource "aws_iam_role_policy" "alb_controller" {
  name = "${var.project_name}-${var.environment}-alb-controller-policy"
  role = aws_iam_role.alb_controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "ec2:GetSecurityGroupsForVpc",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores",
          "elasticloadbalancing:DescribeListenerAttributes"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "CreateSecurityGroup"
          }
          Null = {
            "aws:RequestedRegion" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestedRegion"    = "false"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestedRegion" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          Null = {
            "aws:RequestedRegion"                    = "false"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListenerAttributes"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"]
          }
          Null = {
            "aws:RequestedRegion" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      }
    ]
  })
}

############################################
# IRSA — External Secrets Operator
#
# ESO runs in the cluster and syncs AWS Secrets
# Manager secrets → Kubernetes Secrets.
# It needs read-only access to specific secret paths.
#
# Trust condition: only the "external-secrets"
# ServiceAccount in the "external-secrets" namespace.
############################################

resource "aws_iam_role" "external_secrets" {
  name = "${var.project_name}-${var.environment}-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_host}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-external-secrets-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "${var.project_name}-${var.environment}-external-secrets-policy"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ESO needs to read secret values to sync them into K8s
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        # Scoped to this project+environment's secrets only
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.environment}-*"
      },
      {
        # ESO needs to list secrets to watch for changes
        Effect   = "Allow"
        Action   = ["secretsmanager:ListSecrets"]
        Resource = "*"
      }
    ]
  })
}

############################################
# IRSA — API Service
#
# The api-service pods need the same AWS
# permissions as the ECS task role:
# SQS access + X-Ray tracing + CloudWatch logs.
#
# Trust condition: only the "api-service" SA
# in the "api-service" namespace.
#
# This is the Kubernetes equivalent of
# IRSA-vs-instance-profile: pods get individual
# IAM identities, not shared node-level access.
############################################

resource "aws_iam_role" "api_service" {
  name = "${var.project_name}-${var.environment}-eks-api-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_host}:sub" = "system:serviceaccount:api-service:api-service"
          "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-api-service-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "api_service" {
  name = "${var.project_name}-${var.environment}-eks-api-service-policy"
  role = aws_iam_role.api_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.project_name}-${var.environment}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/eks/${var.project_name}-${var.environment}*"
      }
    ]
  })
}

############################################
# SQS — Karpenter Spot Interruption Queue
#
# Karpenter's interruption handler listens for
# EC2 Spot interruption notices, rebalance
# recommendations, and instance state changes
# via EventBridge → SQS.
#
# When Karpenter receives an interruption signal
# for a Spot node, it proactively:
#   1. Cordons the node (no new pods scheduled)
#   2. Drains the node (evicts existing pods)
#   3. Terminates the node
# This gives workloads a full ~2 minutes to
# gracefully shut down before forced interruption.
#
# Without this: pods are killed with no warning.
# With this: graceful shutdown, zero data loss.
############################################

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.project_name}-${var.environment}-karpenter-interruption"
  message_retention_seconds = 300 # 5 minutes — interruption notices expire quickly

  # Protect against accidental queue deletion
  # (losing the queue means losing interruption handling)

  tags = {
    Name        = "${var.project_name}-${var.environment}-karpenter-interruption"
    Environment = var.environment
    ManagedBy   = "karpenter"
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeToSendMessages"
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "sqs.amazonaws.com"
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

############################################
# EventBridge Rules — Spot Interruption Notifications
#
# These rules route AWS lifecycle events to the
# Karpenter SQS queue. Karpenter's controller
# polls the queue and acts on them.
#
# Events captured:
#   SpotInterruptionWarning: 2-min Spot eviction notice
#   RebalanceRecommendation: AWS recommends proactive rebalance
#   InstanceStateChange:     EC2 instance terminated/stopped
#   ScheduledChange:         AWS planned maintenance
############################################

resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name        = "${var.project_name}-${var.environment}-karpenter-spot-interruption"
  description = "Karpenter: EC2 Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name        = "${var.project_name}-${var.environment}-karpenter-rebalance"
  description = "Karpenter: EC2 Instance Rebalance Recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state" {
  name        = "${var.project_name}-${var.environment}-karpenter-instance-state"
  description = "Karpenter: EC2 Instance State Change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_scheduled_change" {
  name        = "${var.project_name}-${var.environment}-karpenter-scheduled-change"
  description = "Karpenter: AWS Health Scheduled Change"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
}

# Route all Karpenter events to the SQS queue
resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule = aws_cloudwatch_event_rule.karpenter_rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state" {
  rule = aws_cloudwatch_event_rule.karpenter_instance_state.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_scheduled_change" {
  rule = aws_cloudwatch_event_rule.karpenter_scheduled_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

############################################
# IRSA — Karpenter Controller
#
# Karpenter needs broad EC2 permissions because
# it manages the ENTIRE node lifecycle:
#   - Launch: RunInstances, CreateFleet
#   - Terminate: TerminateInstances
#   - Describe: to find available capacity
#   - Tag: to track ownership
#   - IAM PassRole: to assign instance profiles
#   - SQS: to read interruption queue
#   - SSM: to fetch latest EKS-optimized AMI IDs
#
# This is wider than Cluster Autoscaler (which only
# calls SetDesiredCapacity on existing ASGs).
# Karpenter trades narrower permissions for better
# bin-packing and faster scale-out (direct EC2 API).
#
# Trust condition: only the "karpenter" ServiceAccount
# in the "karpenter" namespace can assume this role.
############################################

resource "aws_iam_role" "karpenter" {
  name = "${var.project_name}-${var.environment}-karpenter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_host}:sub" = "system:serviceaccount:karpenter:karpenter"
          "${local.oidc_issuer_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
################################################################################
# AWS WAFv2 — Application Firewall for EKS ALB
#
# Provides an 'Elite' layer of protection against:
#   1. SQL Injection (SQLi)
#   2. Cross-site scripting (XSS)
#   3. Common vulnerabilities (Log4j, etc.)
#   4. High-frequency request floods (Rate Limiting)
#
# The ALB Controller will associate this WebACL with the Ingress ALB
# via the 'alb.ingress.kubernetes.io/wafv2-acl-arn' annotation.
################################################################################

resource "aws_wafv2_web_acl" "eks" {
  name        = "${var.project_name}-${var.environment}-eks-waf"
  description = "WAF for ${var.project_name} EKS ALB Ingress"
  scope       = "REGIONAL" # Regional for ALB (not CloudFront)

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf-metrics"
    sampled_requests_enabled   = true
  }

  # Rule 1: AWS Managed Core Rule Set (protects against common exploits)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: Rate Limiting (Elite protection against request floods)
  rule {
    name     = "RateLimit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000 # Max 2000 requests per 5 minutes per IP
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks-waf"
    Environment = var.environment
  }
}

output "waf_web_acl_arn" {
  description = "ARN of the WAFv2 WebACL for the EKS Ingress"
  value       = aws_wafv2_web_acl.eks.arn
}

  tags = {
    Name        = "${var.project_name}-${var.environment}-karpenter-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "karpenter" {
  name = "${var.project_name}-${var.environment}-karpenter-policy"
  role = aws_iam_role.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # EC2: Karpenter creates and manages node instances directly
        # (not via ASG like Cluster Autoscaler)
        Sid    = "EC2NodeLaunchAndTerminate"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory"
        ]
        Resource = "*"
      },
      {
        # IAM: Karpenter must pass the node instance profile to EC2
        # so launched nodes can assume the node role for ECR, CW, etc.
        Sid    = "IAMPassRoleForNodes"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = aws_iam_role.eks_node_group.arn
      },
      {
        # SQS: read from the interruption queue for Spot handling
        Sid    = "SQSInterruptionQueue"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      },
      {
        # SSM: fetch latest EKS-optimised AMI IDs for the current K8s version
        # Karpenter uses SSM Parameter Store to resolve AMI IDs dynamically
        # instead of hardcoding AMI IDs that rot over time.
        Sid    = "SSMAMILookup"
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/eks/optimized-ami/*"
      },
      {
        # Pricing: Karpenter queries EC2 Spot pricing to make cost-aware
        # instance selection decisions (picks cheapest instance with capacity)
        Sid      = "EC2SpotPricing"
        Effect   = "Allow"
        Action   = ["pricing:GetProducts"]
        Resource = "*"
      },
      {
        # EKS: Karpenter needs to know the cluster endpoint and cert to
        # bootstrap new nodes into the cluster
        Sid      = "EKSDescribeCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.main.arn
      }
    ]
  })
}

# Instance profile: Karpenter attaches this to EC2 instances it launches.
# It must use the same role as the managed node group so Karpenter nodes
# have the same ECR/CW/CNI permissions as the existing node group.
resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.project_name}-${var.environment}-karpenter-node-profile"
  role = aws_iam_role.eks_node_group.name

  tags = {
    Name        = "${var.project_name}-${var.environment}-karpenter-node-profile"
    Environment = var.environment
  }
}
