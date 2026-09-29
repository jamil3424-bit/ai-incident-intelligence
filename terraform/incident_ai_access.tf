resource "aws_iam_role_policy" "incident_analyzer_ai_access" {
  name = "ai-incident-analyzer-ai-access"
  role = aws_iam_role.incident_analyzer_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ReadTestApplicationLogs"
        Effect = "Allow"

        Action = [
          "logs:FilterLogEvents"
        ]

        Resource = "${aws_cloudwatch_log_group.test_application.arn}:*"
      },
      {
        Sid    = "InvokeNovaPro"
        Effect = "Allow"

        Action = [
          "bedrock:InvokeModel"
        ]

        Resource = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-pro-v1:0"
      }
    ]
  })
}
