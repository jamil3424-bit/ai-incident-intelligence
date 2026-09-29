# AI Incident Intelligence — Operations Runbook

## Purpose

This runbook provides the operational procedures used to test, verify, troubleshoot, and validate the AI Incident Intelligence system.

The goal is to provide a repeatable process for confirming that the complete incident-response pipeline is functioning correctly.

---

## System Flow

```text
Test Application Lambda
        ↓
Amazon CloudWatch
        ↓
CloudWatch Alarm
        ↓
Amazon EventBridge
        ↓
Incident Analyzer Lambda
        ↓
CloudWatch Log Evidence
        ↓
Amazon Bedrock / Nova Pro
        ↓
Amazon DynamoDB
```

---

## Prerequisites

Before running operational tests, confirm:

- AWS CLI authentication is working
- AWS region is `us-east-1`
- Terraform infrastructure has been deployed
- Test Application Lambda exists
- Incident Analyzer Lambda exists
- CloudWatch alarm exists
- EventBridge routing exists
- DynamoDB table exists
- Bedrock model access is available

Confirm AWS identity:

```bash
aws sts get-caller-identity
```

Confirm the project directory:

```bash
cd ~/ai-incident-intelligence
pwd
```

---

## Procedure 1 — Verify Terraform State

Move into the Terraform directory:

```bash
cd ~/ai-incident-intelligence/terraform
```

Run:

```bash
terraform fmt -check
terraform validate
terraform plan
```

Expected final state:

```text
No changes. Your infrastructure matches the configuration.
```

If Terraform proposes unexpected changes, do not apply them immediately.

Review:

- resource additions
- in-place changes
- deletions
- replacements
- IAM changes
- affected dependencies

before continuing.

---

## Procedure 2 — Check Current Alarm State

Run:

```bash
aws cloudwatch describe-alarms \
  --alarm-names ai-incident-test-application-errors \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' \
  --output table
```

For a healthy idle system, the alarm should normally show:

```text
OK
```

Missing datapoints may be treated as non-breaching depending on the configured alarm behavior.

---

## Procedure 3 — Trigger a Controlled Failure

Invoke the test Lambda:

```bash
aws lambda invoke \
  --function-name ai-incident-test-application \
  --payload '{"simulate_failure":true}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/ai-incident-test.json
```

Expected Lambda invocation metadata may include:

```text
StatusCode: 200
FunctionError: Unhandled
```

The `FunctionError` is expected because this procedure intentionally generates a failure.
---

## Procedure 4 — Wait for CloudWatch Alarm Evaluation

CloudWatch metric evaluation is asynchronous.

After triggering the controlled failure, wait for the Lambda `Errors` metric to be published and evaluated.

Check the alarm again:

```bash
aws cloudwatch describe-alarms \
  --alarm-names ai-incident-test-application-errors \
  --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' \
  --output table
```

Expected transition:

```text
OK → ALARM
```

If the alarm still shows `OK`, verify that:

- the test Lambda actually failed
- the `Errors` metric received a datapoint
- the evaluation period has elapsed
- the alarm threshold is correct
- missing data behavior is understood

Do not immediately modify the alarm configuration unless the evidence shows the alarm is misconfigured.

---

## Procedure 5 — Verify Incident Analyzer Execution

Check the Incident Analyzer logs:

```bash
aws logs tail /aws/lambda/ai-incident-analyzer \
  --since 15m \
  --format short
```

Look for:

```text
INCIDENT_EVENT
LOG_EVIDENCE
BEDROCK_ANALYSIS
INCIDENT_STORED
```

These markers indicate that the major incident-processing stages executed.

If `INCIDENT_EVENT` is missing, investigate:

```text
CloudWatch Alarm
EventBridge rule
EventBridge target
Lambda invoke permission
```

If `INCIDENT_EVENT` exists but later markers are missing, continue troubleshooting from the analyzer stage forward.

---

## Procedure 6 — Verify CloudWatch Evidence Retrieval

Within the Incident Analyzer logs, confirm that the retrieved evidence includes application-level failure information.

Expected evidence may include:

```text
[ERROR] RuntimeError
Traceback
lambda_function.py
Simulated application failure for incident-response testing.
```

This confirms that the analyzer is using actual workload evidence rather than only alarm metadata.

If evidence is missing, verify:

```text
SOURCE_LOG_GROUP
logs:FilterLogEvents permission
log group name
incident timestamp window
```

---

## Procedure 7 — Verify Bedrock Analysis

Within the analyzer logs, locate:

```text
BEDROCK_ANALYSIS
```

The structured response should contain fields such as:

```text
incident_summary
severity
likely_root_cause
evidence
recommended_actions
confidence
```

For the controlled failure test, the expected result should reflect the simulated application failure.

Example validated values:

```text
severity = LOW
confidence = HIGH
```

If Bedrock analysis fails, verify:

```text
BEDROCK_MODEL_ID
bedrock:InvokeModel permission
AWS region
model availability
response parsing
```

The incident should still be preserved even if AI analysis fails.

---

## Procedure 8 — Verify DynamoDB Persistence

From the analyzer logs, capture the generated incident ID shown after:

```text
INCIDENT_STORED:
```

Then query DynamoDB:

```bash
aws dynamodb get-item \
  --table-name ai-incident-records \
  --key '{"incident_id":{"S":"REPLACE_WITH_INCIDENT_ID"}}' \
  --output json
```

Replace:

```text
REPLACE_WITH_INCIDENT_ID
```

with the actual incident ID.

The returned record should contain both operational metadata and AI analysis.

Expected fields include:

```text
incident_id
alarm_name
timestamp
source
current_state
previous_state
reason
region
analysis_status
ai_analysis
```

For a successful AI test, confirm:

```text
analysis_status = SUCCESS
```

and verify that the stored AI analysis contains:

```text
incident_summary
severity
likely_root_cause
evidence
recommended_actions
confidence
```
---

## Procedure 9 — Troubleshoot AI Failure Without Losing the Incident

If Amazon Bedrock fails, the system should still preserve the incident.

Check the analyzer logs for:

```text
BEDROCK_ANALYSIS_FAILED
```

or an `analysis_status` value of:

```text
FAILED
```

Then confirm that the incident was still written to DynamoDB.

Expected behavior:

```text
Operational Incident
        ↓
AI Processing Fails
        ↓
Failure Recorded
        ↓
Incident Still Persisted
```

Verify the stored record contains:

```text
analysis_status = FAILED
analysis_error
```

This confirms that the AI layer is not a single point of failure.

---

## Procedure 10 — Validate IAM Problems

If a service call fails with `AccessDenied`, identify the exact AWS API action involved before changing permissions.

Common required actions in this project include:

```text
dynamodb:PutItem
logs:FilterLogEvents
bedrock:InvokeModel
```

Do not replace a narrow policy with broad access unless there is clear evidence it is required.

The troubleshooting sequence should be:

```text
AccessDenied
      ↓
Identify failed API
      ↓
Identify target resource
      ↓
Review current IAM policy
      ↓
Add minimum required permission
      ↓
Retest
```

---

## Procedure 11 — Verify EventBridge Routing

If the CloudWatch alarm reaches `ALARM` but the Incident Analyzer does not execute, verify the EventBridge path.

Check the rule:

```bash
aws events describe-rule \
  --name ai-incident-alarm-router
```

Check the configured target:

```bash
aws events list-targets-by-rule \
  --rule ai-incident-alarm-router
```

Confirm that the target points to the Incident Analyzer Lambda.

Also verify that the Lambda allows EventBridge invocation.

The expected architecture is:

```text
CloudWatch Alarm
      ↓
EventBridge Rule
      ↓
EventBridge Target
      ↓
Lambda Invoke Permission
      ↓
Incident Analyzer
```

---

## Procedure 12 — Final Terraform Verification

After testing and troubleshooting are complete, return to the Terraform directory:

```bash
cd ~/ai-incident-intelligence/terraform
```

Run:

```bash
terraform fmt -check
terraform validate
terraform plan
```

Expected final result:

```text
No changes. Your infrastructure matches the configuration.
```

A clean final plan confirms that the deployed AWS environment matches the Infrastructure as Code definition.

---

## Recovery Checklist

If the pipeline does not behave as expected, verify the system in this order:

```text
1. Test Lambda actually failed
2. CloudWatch Errors metric received data
3. CloudWatch alarm transitioned to ALARM
4. EventBridge matched the event
5. EventBridge invoked the Incident Analyzer
6. Analyzer parsed the event successfully
7. Analyzer retrieved CloudWatch evidence
8. Bedrock invocation succeeded or failed safely
9. DynamoDB stored the incident
10. Terraform still matches deployed infrastructure
```

This sequence minimizes guesswork and helps isolate the failing layer quickly.

---

## Completion Checklist

Before considering the system healthy, confirm:

- Terraform validation succeeds
- Terraform plan shows no unexpected changes
- controlled Lambda failure works
- CloudWatch alarm transitions to `ALARM`
- EventBridge invokes the Incident Analyzer
- CloudWatch evidence is retrieved
- Bedrock produces structured incident analysis
- DynamoDB stores the complete record
- AI failure does not prevent incident persistence
- final Terraform plan reports zero drift

---

## Operational Principle

The system should be operated using evidence, not assumptions.

Preferred workflow:

```text
Observe
   ↓
Verify
   ↓
Collect Evidence
   ↓
Identify Root Cause
   ↓
Apply Smallest Change
   ↓
Retest
   ↓
Confirm Downstream Health
```

The purpose of the runbook is to keep incident-response testing repeatable, controlled, and easy to validate.
