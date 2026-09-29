data "archive_file" "incident_analyzer" {
  type        = "zip"
  source_file = "${path.module}/../lambda/incident_analyzer/lambda_function.py"
  output_path = "${path.module}/incident_analyzer.zip"
}

resource "aws_iam_role" "incident_analyzer_lambda_role" {
  name = "ai-incident-analyzer-role"

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

resource "aws_iam_role_policy_attachment" "incident_analyzer_basic_execution" {
  role       = aws_iam_role.incident_analyzer_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "incident_analyzer_dynamodb_write" {
  name = "ai-incident-analyzer-dynamodb-write"
  role = aws_iam_role.incident_analyzer_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "dynamodb:PutItem"
        ]

        Resource = aws_dynamodb_table.incident_records.arn
      }
    ]
  })
}

resource "aws_lambda_function" "incident_analyzer" {
  function_name = "ai-incident-analyzer"

  filename         = data.archive_file.incident_analyzer.output_path
  source_code_hash = data.archive_file.incident_analyzer.output_base64sha256

  role    = aws_iam_role.incident_analyzer_lambda_role.arn
  handler = "lambda_function.lambda_handler"
  runtime = "python3.14"

  timeout     = 30
  memory_size = 128

  environment {
    variables = {
      INCIDENT_TABLE_NAME = aws_dynamodb_table.incident_records.name
      SOURCE_LOG_GROUP    = aws_cloudwatch_log_group.test_application.name
      BEDROCK_MODEL_ID    = "amazon.nova-pro-v1:0"
    }
  }
}

resource "aws_cloudwatch_log_group" "incident_analyzer" {
  name              = "/aws/lambda/${aws_lambda_function.incident_analyzer.function_name}"
  retention_in_days = 7
}
