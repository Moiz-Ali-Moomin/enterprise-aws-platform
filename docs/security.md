# Security & Compliance

## Security Model: Defense in Depth

### 1. Perimeter Security
- **CloudFront + WAF**: Global DDoS protection and SQLi/XSS filtering.
- **Anycast IPs**: Shielding against IP-based attacks via Global Accelerator.

### 2. Network Security
- **Zero Trust**: Every service-to-service request is signed with IAM headers using **VPC Lattice**.
- **PrivateLink**: AWS service communication stays within the AWS Private Network.

### 3. Supply Chain Security
- **Image Signing**: All images are cryptographically signed using **Cosign**.
- **SBOM**: A software bill of materials is generated for every container build to track vulnerabilities.
- **Image Scanning**: Trivy scans fail the build on `HIGH` or `CRITICAL` findings.

### 4. Identity & Access Management
- **Least Privilege**: All IAM roles have strict `Action` and `Resource` filters.
- **Permission Boundaries**: Global boundaries prevent roles from escalating their own privileges.

## Compliance (SOC2 Ready)
- **Encryption at Rest**: Mandatory KMS encryption for S3, SQS, and RDS.
- **Encryption in Transit**: TLS 1.2+ required at all endpoints.
- **Audit Logging**: CloudTrail and VPC Flow Logs are enabled Organization-wide and sent to a dedicated Audit account.
