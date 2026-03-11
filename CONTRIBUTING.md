# Contributing to the Enterprise Platform

We welcome contributions! Please follow this workflow to maintain our 10/10 production quality.

## Development Workflow
1. **Fork then Pull**: Create a feature branch from `main`.
2. **Lint and Test**:
   - Run `tflint` on all Terraform modules.
   - Run `checkov` to ensure no security regressions.
3. **Commit Messages**: Follow [Conventional Commits](https://www.conventionalcommits.org/).

## Coding Standards
- **Terraform**: Must be modular and include a `README.md` for each module.
- **Python**: Must follow PEP8 and include OTel instrumentation.
- **Security**: Never commit secrets or hardcoded IAM policies.

## PR Review Process
- At least 2 approvals required for changes to `terraform/environments/prod`.
- All CI checks (Security, Lint, Plan) must pass.
