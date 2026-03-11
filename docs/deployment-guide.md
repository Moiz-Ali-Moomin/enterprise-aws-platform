# Elite Deployment Orchestration Guide

This guide details the **10/10 elite-grade orchestration** required to provision and maintain the global platform. Follow these steps to ensure compliance, security, and world-class reliability.

## 1. Zero-Touch State Bootstrapping
Elite DevOps never manually manage state. We use an automated 'Bootstrap' layer to establish the remote backend with S3 Cross-Region Replication and DynamoDB global locking.

```bash
cd terraform/bootstrap
terraform init
terraform apply -auto-approve
```
*Note: This creates the source of truth for all subsequent regional and global infrastructure.*

## 2. Multi-Account AWS Organization
Our platform is governed by an **AWS Organization**. This step defines the Security, Shared Services, and Workload accounts, ensuring absolute blast-radius isolation.

```bash
cd terraform/org-structure
terraform init
terraform plan -out=org.plan
terraform apply org.plan
```

## 3. Global Edge & Anycast Provisioning
Before regional workloads, we establish the global edge tier. This includes **AWS Global Accelerator** and **hardened WAF policies** that shield the platform across all regional entry points.

```bash
cd terraform/global
terraform init
terraform apply
```

## 4. Policy-Enforced Environment Deployment
All infrastructure changes are validated against **Elite Compliance Policies (Checkov/OPA)** before execution.

```bash
# Example for Production
cd terraform/environments/prod
terraform init
terraform plan -out=prod.plan
# The CI pipeline automatically runs security linting here
terraform apply prod.plan
```

## 5. Progressive Application Delivery (GitOps + Canary)
Elite deployments avoid "Big Bang" updates. We use a **Progressive Delivery** model:

1. **Supply Chain Check**: The CI pipeline (`hardened-app-ci.yml`) builds the OCI image, generates an **SBOM**, and signs the artifact with **Cosign**.
2. **Vuln Scan**: Images are scanned with **Trivy**; High/Critical findings stop the line.
3. **Canary Rollout**: The `canary_deploy.py` script orchestrates a weighted traffic shift (10% -> 50% -> 100%) while monitoring SQS depth and API error rates.

## 6. Automated Validation & Self-Healing
Once deployed, the platform is automatically verified:
- **X-Ray Analysis**: Automated trace sampling checks for latency spikes across regions.
- **Chaos Validation**: Periodically, **AWS FIS** experiments test the failover logic of the new deployment.
- **Auto-Rollback**: CloudWatch Alarms are tied to the deployment controller; any Breach of Error Budget during rollout triggers an instant, automated rollback.

---

## Deployment & Redeployment Operations

### 1. Live Production Details
**Public URL:** [http://ecs-enterprise-prod-alb-250114052.us-east-1.elb.amazonaws.com](http://ecs-enterprise-prod-alb-250114052.us-east-1.elb.amazonaws.com)
**Health Endpoint:** `/health`

### 2. Redeployment Procedure (No-Docker)
To update the application without local Docker, use the automated CodeBuild pipeline:

1. **Package Source**:
   ```powershell
   # From project root
   tar -acf project.zip .github ansible docs monitoring scripts services buildspec.yml README.md
   ```

2. **Upload to S3**:
   ```powershell
   aws s3 cp project.zip s3://ecs-enterprise-platform-terraform-state/source/project.zip
   ```

3. **Trigger Build**:
   ```powershell
   aws codebuild start-build --project-name ecs-enterprise-prod-build --region us-east-1
   ```

4. **Update ECS Service**:
   Once the build succeeds, force a new deployment:
   ```powershell
   aws ecs update-service --cluster ecs-enterprise-prod-cluster --service ecs-enterprise-prod-service --force-new-deployment --region us-east-1
   ```

### 3. Verification
Verify the healthy rollout:
```powershell
curl.exe -f http://ecs-enterprise-prod-alb-250114052.us-east-1.elb.amazonaws.com/health
```
