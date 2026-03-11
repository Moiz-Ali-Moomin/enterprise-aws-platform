resource "aws_sfn_state_machine" "main" {
  name     = "${var.project_name}-${var.environment}-workflow"
  role_arn = var.step_functions_role_arn

  definition = jsonencode({
    Comment = "A simple AWS Step Functions state machine"
    StartAt = "HelloWorld"
    States = {
      HelloWorld = {
        Type     = "Task"
        Resource = var.lambda_function_arn
        End      = true
      }
    }
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-sfn"
    Environment = var.environment
  }
}
