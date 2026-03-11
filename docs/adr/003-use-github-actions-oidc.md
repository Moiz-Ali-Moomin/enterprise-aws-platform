# ADR 003: Use GitHub OIDC for AWS Authentication

## Status
Accepted

## Context
Storing long-lived AWS IAM User access keys in GitHub Secrets is a major security risk. Keys are often over-privileged and difficult to rotate.

## Decision
We implemented OpenID Connect (OIDC) authentication between GitHub Actions and AWS.

## Consequences
- **Pros**: Short-lived, scoped credentials; no secrets stored in GitHub; automated credential rotation; and identity-based auditing in CloudTrail.
- **Cons**: Requires initial Terraform setup of the OIDC provider and roles.
