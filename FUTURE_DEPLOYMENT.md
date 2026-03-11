# Step-by-Step Deployment Manual: ECS Enterprise Platform

This guide provides the exact sequence of commands and procedures to deploy or redeploy the platform to AWS from scratch or for updates. This workflow is optimized for environments **without local Docker**, utilizing AWS CodeBuild for cloud-native containerization.

---

## 📋 Prerequisites
- **AWS CLI** installed and configured with appropriate permissions.
- **Terraform** installed (v1.0+ recommended).
- **PowerShell** or **Bash** terminal.

---

## 🚀 Phase 1: Infrastructure Bootstrapping
*Required only once per AWS account/region.*

1. **Navigate to Bootstrap Directory**:
   ```bash
   cd terraform/bootstrap
   ```

2. **Initialize and Apply**:
   ```bash
   terraform init
   ```
   ```bash
   terraform apply -auto-approve
   ```
   *This creates the S3 bucket for Terraform state and the DynamoDB table for state locking.*

---

## 🏗️ Phase 2: Provision Production Infrastructure

1. **Navigate to Production Environment**:
   ```bash
   cd ../environments/prod
   ```

2. **Initialize with Remote Backend**:
   ```bash
   terraform init -reconfigure
   ```

3. **Deploy Infrastructure**:
   ```bash
   terraform apply -auto-approve
   ```
   *This provisions the VPC, IAM roles, ECR repository, CodeBuild project, ECS cluster, and ALB.*

---

## 📦 Phase 3: Automated Application Deployment
*Perform these steps whenever you want to update the application code.*

### 1. Package the Source Code
You must bundle the project into a `.zip` file for CodeBuild.

**PowerShell Optimized**:
```powershell
# Remove old zips to keep it clean
Remove-Item *.zip -Force -ErrorAction SilentlyContinue

# Create archive including all necessary context (exclude large/git folders)
tar -acf project.zip .github ansible docs monitoring scripts services buildspec.yml README.md
```

### 2. Upload to S3
Upload the archive to the source bucket defined in your Terraform variables.

```bash
aws s3 cp project.zip s3://ecs-enterprise-platform-terraform-state/source/project.zip
```

### 3. Trigger the Cloud Build
Start the CodeBuild project to build the Docker image and push it to ECR.

```bash
aws codebuild start-build --project-name ecs-enterprise-prod-build --region us-east-1
```

### 4. Monitor the Build
You can check progress in the AWS Console or via CLI:
```bash
aws codebuild batch-get-builds --ids <BUILD_ID_FROM_PREVIOUS_STEP> --region us-east-1 --query "builds[0].buildStatus"
```

---

## 🚢 Phase 4: ECS Service Update
*After CodeBuild confirms 'SUCCEEDED'.*

Trigger ECS to pull the new image from ECR and perform a rolling update.

```bash
aws ecs update-service --cluster ecs-enterprise-prod-cluster --service ecs-enterprise-prod-service --force-new-deployment --region us-east-1
```

---

## ✅ Phase 5: Verification

1. **Get the ALB DNS Name**:
   ```bash
   cd terraform/environments/prod
   terraform output album_dns_name
   ```

2. **Check Health Endpoint**:
   ```bash
   curl -f http://<ALB_DNS_NAME>/health
   ```
   *Expected response: `{"status":"healthy"}`*

---

## 🛠️ Operations & Troubleshooting

- **Logs**: If the build fails, check CloudWatch logs:
  `/aws/codebuild/ecs-enterprise-prod-build`
- **Container Logs**: Check ECS task logs in CloudWatch:
  `/ecs/ecs-enterprise-prod`
- **Redeployment**: Simply repeat **Phase 3** (Packaging/Upload/Build) and **Phase 4** (Service Update).

---
**Elite DevOps Principle**: "Infrastructure is code, and code is documented."
