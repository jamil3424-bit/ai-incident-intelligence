# AI Incident Intelligence — Troubleshooting Log

## Purpose

This document records meaningful issues encountered while building AI Incident Intelligence, how they were diagnosed, the root cause, and the resolution.

The goal is to preserve engineering reasoning rather than only documenting the final working state.

---

## Issue 1 — Incorrect File Path / Working Directory

### Symptom

While attempting to inspect the Incident Analyzer source file, the command returned:

```text
No such file or directory
```

The expected path was:

```text
lambda/incident_analyzer/lambda_function.py
```

### Investigation

The shell was not running from the project root directory.

The relative path was therefore being resolved from the wrong location.

Commands such as:

```bash
pwd
```

and directory navigation were used to confirm the current location.

### Root Cause

The command used a project-root-relative path while the terminal was positioned inside another directory.

### Resolution

Return to the project root before referencing project-relative paths:

```bash
cd ~/ai-incident-intelligence
```

Then verify:

```bash
pwd
```

### Lesson Learned

Before troubleshooting a missing file, first confirm:

```text
current directory
expected relative path
actual file location
```

This prevents a simple path issue from being mistaken for missing code or a failed deployment.

---

## Issue 2 — Terraform Saved Plan Could Not Be Found

### Symptom

Terraform returned:

```text
Failed to load "incident-storage-update.tfplan" as a plan file

stat incident-storage-update.tfplan:
no such file or directory
```

### Investigation

The directory contents were inspected using:

```bash
pwd
ls -lh *.tfplan
```

A saved plan existed, but the exact filename did not match the filename being passed to `terraform apply`.

### Root Cause

There was a filename/path mismatch between the saved Terraform plan and the apply command.

Visually similar dash characters also made the filename harder to identify correctly.

### Resolution

The exact saved plan filename was identified from the filesystem before applying it.

### Preventive Improvement

Use simple ASCII-only Terraform plan names such as:

```text
incident_storage_update.tfplan
final_ai_update.tfplan
```

and verify the file before applying:

```bash
ls -lh final_ai_update.tfplan
```

### Lesson Learned

A Terraform plan should be treated as an exact deployment artifact.

Do not assume the filename.

Verify:

```text
working directory
exact filename
file existence
```

before executing `terraform apply`.
---

## Issue 3 — CloudWatch Alarm Stayed `OK` After a Failure

### Symptom

A controlled Lambda failure was generated successfully, but the CloudWatch alarm initially remained:

```text
OK
```

The alarm reason showed that no datapoint had been received for the evaluation period and that missing data was being treated as non-breaching.

At first glance, this could look like the monitoring configuration was broken.

### Investigation

The Lambda failure itself was verified first.

The test invocation returned an unhandled function error, confirming the application had actually failed.

Next, the CloudWatch alarm state was queried repeatedly rather than changing configuration immediately.

After the new Lambda `Errors` datapoint was published and evaluated, the alarm transitioned to:

```text
ALARM
```

with a reason indicating that one datapoint had reached the configured threshold.

### Root Cause

The issue was not a broken alarm.

There was normal delay between:

```text
Lambda failure
      ↓
metric publication
      ↓
CloudWatch evaluation
      ↓
alarm state transition
```

The alarm was configured with:

```text
treat_missing_data = notBreaching
```

so the period before the error datapoint arrived remained healthy.

### Resolution

No infrastructure change was required.

The correct response was to wait for the CloudWatch metric evaluation cycle and re-check the alarm state.

### Lesson Learned

Monitoring systems are asynchronous.

Do not immediately modify infrastructure just because an expected state transition has not appeared yet.

First verify:

- the workload actually failed
- the metric exists
- the alarm threshold is correct
- the evaluation period has elapsed
- the state eventually reflects the datapoint

This prevented an unnecessary configuration change to a correctly functioning alarm.

---

## Issue 4 — Verifying EventBridge Actually Invoked the Analyzer

### Symptom

After the CloudWatch alarm transitioned to `ALARM`, the next question was whether EventBridge had successfully routed the state-change event to the Incident Analyzer.

A successful alarm by itself did not prove the downstream Lambda was being invoked.

### Investigation

The Incident Analyzer CloudWatch log group was queried directly.

The logs contained:

```text
INCIDENT_EVENT:
```

followed by structured alarm metadata including:

```text
alarm_name
current_state = ALARM
previous_state = OK
reason
timestamp
region
source
```

### Root Cause

There was no routing failure.

The uncertainty came from validating one layer of the architecture at a time.

### Resolution

The analyzer logs were used as direct evidence that the EventBridge target and Lambda invocation permission were working.

### Lesson Learned

For event-driven systems, verify each hop independently.

The validation sequence became:

```text
Application failure
→ CloudWatch alarm
→ EventBridge routing
→ Lambda invocation
→ downstream processing
```

This makes it much easier to identify the exact layer responsible when a pipeline fails.---

## Issue 5 — DynamoDB Write Permission Needed for Incident Persistence

### Symptom

The Incident Analyzer could process alarm events, but the architecture still needed durable incident storage.

Once DynamoDB persistence was added to the Python code, the Lambda also required permission to write to the table.

### Investigation

The required operation was identified as:

```text
dynamodb:PutItem
```

Rather than attaching a broad DynamoDB policy, the required action and target table were isolated.

### Root Cause

The existing Lambda execution role allowed basic Lambda logging, but it did not include permission to write incident records into DynamoDB.

### Resolution

A dedicated IAM policy was added with:

```text
Action:
dynamodb:PutItem
```

scoped to:

```text
ai-incident-records
```

The Incident Analyzer also received the table name through the environment variable:

```text
INCIDENT_TABLE_NAME
```

### Validation

After the IAM update, the analyzer logged:

```text
INCIDENT_STORED:
```

The exact incident was then queried directly from DynamoDB and returned successfully.

### Lesson Learned

Application code and IAM permissions must evolve together.

When a workload gains a new responsibility:

```text
new capability
      ↓
required API action
      ↓
minimum IAM permission
      ↓
specific resource scope
```

This keeps functionality and security aligned.

---

## Issue 6 — Validate Amazon Bedrock Before Adding It to the Pipeline

### Symptom

Before Bedrock could be added to the Incident Analyzer, it was necessary to determine whether model invocation itself worked correctly in the AWS account and region.

Testing Bedrock only after embedding it into the Lambda would have made failures harder to isolate.

### Investigation

Amazon Nova Pro was invoked independently using the AWS CLI.

The validation request returned:

```text
BEDROCK_READY
```

A second test supplied representative incident evidence and successfully returned structured analysis.

### Root Cause

There was no Bedrock configuration failure.

The independent validation was performed proactively to reduce future troubleshooting complexity.

### Resolution

Bedrock access, model availability, authentication, region, and response behavior were confirmed before integrating the model into the Incident Analyzer.

### Lesson Learned

Validate external dependencies independently.

Before connecting a new service into an existing pipeline, prove:

- authentication works
- the service is available
- the region is correct
- the selected resource exists
- the expected API call works
- the response format is understood

This dramatically reduces the troubleshooting surface during integration.

---

## Issue 7 — Bedrock Returned JSON Inside Markdown Code Fences

### Symptom

The prompt requested valid JSON only, but the model response could still be wrapped in Markdown fences similar to:

```text
```json
{ ... }
```
```

A human can read this correctly, but a direct call to:

```python
json.loads()
```

would fail if the Markdown markers remained.

### Investigation

The Bedrock response format was inspected before automating JSON parsing.

The content itself was valid structured JSON, but the surrounding Markdown formatting needed to be removed defensively.

### Root Cause

Large language models can follow the requested schema while still adding presentation formatting.

The application therefore could not assume the output would always be raw JSON.

### Resolution

A defensive parsing function was added to remove optional Markdown code fences before calling `json.loads()`.
### Resolution

A defensive parsing function was added to remove optional Markdown code fences before calling `json.loads()`.

The logic handles both JSON-labeled Markdown code fences and generic Markdown code fences before parsing the response.

### Lesson Learned

Never make downstream automation depend on perfect model formatting.

AI responses should be validated, normalized, and parsed defensively before being trusted by another system.

---

## Issue 8 — Incident Analyzer Timeout Became Too Short

### Symptom

The Incident Analyzer originally used a 10-second Lambda timeout.

That worked when the function mainly parsed events and stored incident metadata.

After adding CloudWatch log retrieval and Amazon Bedrock inference, the execution path became longer.

### Investigation

The complete execution path now included:

```text
Receive EventBridge event
        ↓
Retrieve CloudWatch logs
        ↓
Build Bedrock request
        ↓
Invoke Amazon Nova Pro
        ↓
Parse structured response
        ↓
Write incident to DynamoDB
```

Each AWS service call introduces additional latency.

### Root Cause

The original timeout no longer reflected the analyzer's actual workload.

### Resolution

The Lambda timeout was increased from:

```text
10 seconds
```

to:

```text
30 seconds
```

### Lesson Learned

Runtime configuration should evolve with application behavior.

Timeouts should provide enough headroom for legitimate service calls while remaining bounded.

---

## Issue 9 — AI Integration Required Additional IAM Permissions

### Symptom

The Incident Analyzer gained two new responsibilities:

- retrieving CloudWatch evidence
- invoking Amazon Bedrock

The existing execution role did not include these permissions.

### Investigation

The exact AWS API operations required by the new functionality were identified.

CloudWatch Logs required:

```text
logs:FilterLogEvents
```

Amazon Bedrock required:

```text
bedrock:InvokeModel
```

### Root Cause

The IAM role correctly represented the earlier application design but needed to evolve as functionality was added.

### Resolution

A dedicated IAM policy was added granting only the required actions.

CloudWatch access was scoped to the test application's log group.

Bedrock invocation was scoped to the Amazon Nova Pro model used by the project.

Broad permissions such as:

```text
logs:*
bedrock:*
```

were intentionally avoided.

### Lesson Learned

New functionality should lead to deliberate IAM expansion, not broad access.
---

## Issue 10 — Confirming the Entire AI Pipeline Worked

### Symptom

Individual AWS components had already been validated, but that did not prove the complete distributed workflow functioned end to end.

A full system test was required.

### Investigation

A controlled failure was triggered in the test application.

The workflow was then validated layer by layer.

The CloudWatch alarm transitioned:

```text
OK → ALARM
```

The Incident Analyzer logs showed:

```text
INCIDENT_EVENT
LOG_EVIDENCE
BEDROCK_ANALYSIS
INCIDENT_STORED
```

Amazon Bedrock returned:

```text
severity = LOW
confidence = HIGH
```

and correctly identified the controlled application failure as the likely root cause.

The generated incident was then queried directly from DynamoDB.

The persisted record contained:

```text
analysis_status = SUCCESS
```

along with the structured AI analysis.

### Resolution

The complete workflow was validated:

```text
Lambda Failure
      ↓
CloudWatch
      ↓
CloudWatch Alarm
      ↓
EventBridge
      ↓
Incident Analyzer
      ↓
CloudWatch Evidence
      ↓
Amazon Bedrock
      ↓
DynamoDB
```

### Lesson Learned

Successful component tests do not prove that a distributed system works as a whole.

End-to-end validation is required to prove that service integrations, IAM permissions, event routing, application logic, AI processing, and persistence all work together.

---

## Issue 11 — Final Terraform Drift Verification

### Question

After the application workflow was successfully validated, one final infrastructure question remained:

Did the deployed AWS environment still match the Terraform configuration?

### Investigation

A final Terraform plan was executed:

```bash
terraform plan
```

Terraform refreshed the managed AWS resources and compared the deployed environment against the Infrastructure as Code configuration.

### Result

Terraform returned:

```text
No changes. Your infrastructure matches the configuration.
```

### Resolution

No infrastructure changes were required.

The deployed AWS environment matched the intended Terraform state.

### Lesson Learned

Application validation and infrastructure validation prove different things.

End-to-end testing proves that the workload behaves correctly.

A zero-drift Terraform plan proves that the deployed infrastructure matches its managed configuration.

Both should be verified before declaring a project complete.

---

## Troubleshooting Principles Reinforced

This project reinforced a root-cause-first troubleshooting process:

```text
Observe the symptom
        ↓
Verify the affected layer
        ↓
Collect evidence
        ↓
Identify root cause
        ↓
Make the smallest justified change
        ↓
Retest
        ↓
Validate downstream behavior
        ↓
Verify infrastructure state
```

The goal was to avoid speculative fixes.

Instead, troubleshooting decisions were based on:

- CloudWatch logs
- CloudWatch metrics
- alarm state
- AWS CLI output
- Lambda execution results
- DynamoDB records
- Terraform plans
- Bedrock responses

This kept changes evidence-driven and reduced unnecessary modifications.

---

## Final Result

The completed system successfully:

- generated a controlled Lambda failure
- detected the failure through CloudWatch
- transitioned the alarm from `OK` to `ALARM`
- routed the state-change event through EventBridge
- invoked the Incident Analyzer Lambda
- retrieved real CloudWatch error evidence
- generated structured analysis with Amazon Bedrock
- persisted the complete incident in DynamoDB
- successfully read the incident back
- returned to a zero-drift Terraform state

The troubleshooting process demonstrated not only how to build the system, but how to validate and operate it methodically.
