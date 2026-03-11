# ADR 001: Decommission AWS CodePipeline in Favor of GitHub Actions

## Status
Accepted

## Context
The platform originally used a dual CI/CD approach: GitHub Actions for some checks and AWS CodePipeline/CodeBuild for deployments. This created split-brain logic, increased complexity, and made it difficult to unify security gates (like Trivy scanning and Cosign signing) across the entire lifecycle.

## Decision
We decided to decommission AWS CodePipeline and CodeBuild entirely. All CI/CD logic is now consolidated into GitHub Actions.

## Consequences
- **Pros**: Unified pipeline logic, easier local debugging of workflows, lower AWS costs (no CodePipeline execution fees), and better integration with GitHub-native security features (SBOM, Cosign).
- **Cons**: GitHub Actions becomes a critical dependency for deployments.
- **Mitigation**: Using OIDC for secure, secretless authentication to AWS.
