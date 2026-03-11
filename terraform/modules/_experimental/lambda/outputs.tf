output "lambda_function_arn" {
  value = aws_lambda_function.hello_world.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.hello_world.function_name
}
