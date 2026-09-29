resource "aws_cloudwatch_event_rule" "incident_alarm" {
  name        = "ai-incident-alarm-router"
  description = "Routes AI Incident Intelligence CloudWatch alarms to the Incident Analyzer Lambda."

  event_pattern = jsonencode({
    source = [
      "aws.cloudwatch"
    ]

    "detail-type" = [
      "CloudWatch Alarm State Change"
    ]

    detail = {
      alarmName = [
        aws_cloudwatch_metric_alarm.test_application_errors.alarm_name
      ]

      state = {
        value = [
          "ALARM"
        ]
      }
    }
  })
}

resource "aws_lambda_permission" "allow_eventbridge_incident_analyzer" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.incident_alarm.arn
}

resource "aws_cloudwatch_event_target" "incident_analyzer" {
  rule      = aws_cloudwatch_event_rule.incident_alarm.name
  target_id = "incident-analyzer"
  arn       = aws_lambda_function.incident_analyzer.arn

  depends_on = [
    aws_lambda_permission.allow_eventbridge_incident_analyzer
  ]
}
