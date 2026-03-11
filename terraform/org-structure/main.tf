# AWS Organization Structure
resource "aws_organizations_organization" "org" {
  feature_set = "ALL"
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_account" "security_audit" {
  name      = "SecurityAudit"
  email     = "devops+audit@example.com"
  parent_id = aws_organizations_organizational_unit.security.id
}

resource "aws_organizations_account" "prod" {
  name      = "Production"
  email     = "devops+prod@example.com"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_account" "shared_services" {
  name      = "SharedServices"
  email     = "devops+shared@example.com"
  parent_id = aws_organizations_organization.org.roots[0].id
}
