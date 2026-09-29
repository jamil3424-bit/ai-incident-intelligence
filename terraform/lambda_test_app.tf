data "archive_file" "test_application" {
  type        = "zip"
  source_file = "${path.module}/../lambda/test_application/lambda_function.py"
  output_path = "${path.module}/test_application.zip"
}

resource "aws_iam_role" "test_application_lambda_role" {
  name = "ai-incident-test-application-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "test_application_basic_execution" {
  role       = aws_iam_role.test_application_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "test_application" {
  function_name = "ai-incident-test-application"

  filename         = data.archive_file.test_application.output_path
  source_code_hash = data.archive_file.test_application.output_base64sha256

  role    = aws_iam_role.test_application_lambda_role.arn
  handler = "lambda_function.lambda_handler"
  runtime = "python3.14"

  timeout     = 10
  memory_size = 128
}

resource "aws_cloudwatch_log_group" "test_application" {
  name              = "/aws/lambda/${aws_lambda_function.test_application.function_name}"
  retention_in_days = 7
}
