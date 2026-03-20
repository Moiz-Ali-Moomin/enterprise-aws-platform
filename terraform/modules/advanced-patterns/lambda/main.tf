resource "aws_lambda_function" "hello_world" {
  function_name = "${var.project_name}-${var.environment}-hello-world"
  role          = var.lambda_role_arn
  handler       = "index.handler"
  runtime       = "python3.9"

  filename         = "lambda_function_payload.zip" # Placeholder
  source_code_hash = filebase64sha256("${path.module}/lambda_function_payload.zip")

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda"
    Environment = var.environment
  }
}
