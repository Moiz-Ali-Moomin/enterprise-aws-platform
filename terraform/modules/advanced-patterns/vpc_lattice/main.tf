resource "aws_vpclattice_service_network" "main" {
  name      = "${var.project_name}-lattice-network"
  auth_type = "AWS_IAM" # Zero Trust: Every request must be signed
}

resource "aws_vpclattice_service" "api" {
  name      = "api-service"
  auth_type = "AWS_IAM"
}

resource "aws_vpclattice_service_network_vpc_association" "app_vpc" {
  vpc_identifier             = var.vpc_id
  service_network_identifier = aws_vpclattice_service_network.main.id
  security_group_ids         = [var.vpc_lattice_sg_id]
}

resource "aws_vpclattice_target_group" "ecs_tasks" {
  name = "api-service-targets"
  type = "IP"

  config {
    vpc_identifier = var.vpc_id
    port           = 8000
    protocol       = "HTTP"
  }
}
