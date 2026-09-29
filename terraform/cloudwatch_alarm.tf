resource "aws_cloudwatch_metric_alarm" "test_application_errors" {
  alarm_name        = "ai-incident-test-application-errors"
  alarm_description = "Detects errors in the AI Incident Intelligence test Lambda."

  namespace   = "AWS/Lambda"
  metric_name = "Errors"
  statistic   = "Sum"

  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    FunctionName = aws_lambda_function.test_application.function_name
  }

  treat_missing_data = "notBreaching"
}
