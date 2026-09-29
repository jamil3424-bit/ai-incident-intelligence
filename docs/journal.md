# AI Incident Intelligence — Engineering Journal

## Project Objective

Build an event-driven AI incident-response system on AWS that:

- detects AWS Lambda failures
- routes incidents automatically
- retrieves real operational evidence
- uses Amazon Bedrock for structured root-cause analysis
- persists complete incident records in DynamoDB
- provisions infrastructure with Terraform
- applies least-privilege IAM

The goal was not simply to demonstrate a generative AI API call.

The project was designed to show how AI can operate inside a monitored, secure, observable, and recoverable cloud workflow.

---

## Phase 1 — Controlled Failure Application

The first requirement was a deterministic way to create incidents.

A test AWS Lambda function was created with two execution paths.

Healthy execution:

```json
{
  "simulate_failure": false
}
The function returns normally.

Failure execution:

```json
{
  "simulate_failure": true
}
```

Expected result:

```text
RuntimeError:
Simulated application failure for incident-response testing.
```

### Why This Was Important

Waiting for random application failures would make testing inconsistent.

A controlled failure mechanism allowed the incident pipeline to be tested repeatedly and safely.

---

## Phase 2 — Terraform Infrastructure

Terraform was introduced to provision and manage the AWS environment.

The project used Terraform for:

- Lambda functions
- IAM roles
- IAM policies
- CloudWatch log groups
- CloudWatch alarms
- EventBridge routing
- Lambda permissions
- DynamoDB
- Lambda environment configuration

The standard deployment workflow became:

```text
terraform fmt
terraform validate
terraform plan
review
terraform apply
```

Before each infrastructure change, the Terraform plan was reviewed for resource creation, modification, destruction, and blast radius.

---

## Phase 3 — CloudWatch Failure Detection

Amazon CloudWatch was configured to monitor the test Lambda `Errors` metric.

The alarm threshold was configured to detect:

```text
Errors >= 1
```

During testing, the alarm successfully transitioned:

```text
OK → ALARM
```

This became the event that initiated automated incident processing.

### Lesson Learned

CloudWatch metrics are not necessarily evaluated immediately after an invocation.

During testing, the alarm sometimes remained `OK` temporarily before the new error datapoint was evaluated.

This reinforced the importance of understanding metric publication and evaluation latency rather than assuming an event pipeline is broken immediately.
---

## Phase 4 — Incident Analyzer

A second AWS Lambda function was created to process CloudWatch alarm events.

The Incident Analyzer receives the EventBridge payload and converts it into a normalized incident record containing fields such as:

```text
incident_id
alarm_name
current_state
previous_state
reason
timestamp
region
source
```

The event-processing logic was tested with representative CloudWatch alarm events before relying on the complete AWS event pipeline.

### Why This Helped

Testing the event parser independently reduced the troubleshooting surface.

Instead of debugging CloudWatch, EventBridge, Lambda permissions, and Python parsing at the same time, the application logic could be validated first.

---

## Phase 5 — EventBridge Integration

Amazon EventBridge was added to route CloudWatch alarm state changes automatically.

The rule filters for:

```text
source = aws.cloudwatch
detail-type = CloudWatch Alarm State Change
alarm = ai-incident-test-application-errors
state = ALARM
```

When the rule matches, EventBridge invokes the Incident Analyzer Lambda.

The Lambda also required explicit permission allowing:

```text
events.amazonaws.com
```

to invoke the analyzer.

### Validation

A controlled application failure successfully produced the path:

```text
Test Lambda Failure
        ↓
CloudWatch Alarm
        ↓
EventBridge
        ↓
Incident Analyzer Lambda
```

The Incident Analyzer CloudWatch logs confirmed receipt of the alarm event.

### Engineering Decision

EventBridge was preferred over polling because the system only needs to execute when a meaningful state change occurs.

This creates a more loosely coupled and event-driven architecture.

---

## Phase 6 — DynamoDB Incident Storage

A DynamoDB table was introduced to create durable incident history.

Table:

```text
ai-incident-records
```

Primary key:

```text
incident_id
```

The Incident Analyzer was updated to persist each structured incident record.

The IAM permission required for this operation was:

```text
dynamodb:PutItem
```

and was scoped to the incident table rather than broad DynamoDB access.

### Validation

After triggering a controlled incident, the stored record was retrieved from DynamoDB using its incident ID.

The record contained:

```text
incident_id
alarm_name
timestamp
source
current_state
previous_state
reason
region
```

### Lesson Learned

CloudWatch logs are useful for observing execution, but they are not a substitute for persistent application state.

DynamoDB turned each processed alarm into a durable operational record that could be queried later.
---

## Phase 7 — Operational Evidence Retrieval

The next improvement was to ground incident analysis in real system evidence.

The Incident Analyzer was updated to retrieve CloudWatch log messages from the failed application.

The retrieved evidence included:

```text
[ERROR] RuntimeError
Traceback
lambda_function.py
Simulated application failure for incident-response testing.
```

This changed the architecture from:

```text
Alarm Metadata
      ↓
Incident Record
```

to:

```text
Alarm Metadata
      +
CloudWatch Evidence
      ↓
Incident Analysis
```

### Why This Was Important

An alarm indicates that something went wrong, but it does not necessarily explain why.

Retrieving the actual traceback gives the analysis layer evidence from the workload itself.

This reduced unsupported inference and made the incident analysis more operationally useful.

---

## Phase 8 — Amazon Bedrock Validation

Before integrating Amazon Bedrock into the Incident Analyzer, model access was tested independently.

Amazon Nova Pro was invoked directly and returned the expected response.

This confirmed:

```text
Bedrock access
AWS region
model availability
authentication
CLI invocation
```

before introducing Bedrock into the larger incident-response path.

### Lesson Learned

External dependencies should be validated independently before being embedded into a multi-service workflow.

This reduces the number of variables involved when troubleshooting.

---

## Phase 9 — AI Incident Analysis

After Bedrock access was confirmed, the Incident Analyzer was extended to send incident context and real CloudWatch evidence to Amazon Nova Pro.

The model was asked to return structured JSON containing:

```text
incident_summary
severity
likely_root_cause
evidence
recommended_actions
confidence
```

The prompt also explicitly instructed the model to:

```text
use only the supplied incident evidence
do not invent evidence
return structured output
```

### Final AI Result

During the controlled end-to-end test, Bedrock returned:

```text
severity = LOW
confidence = HIGH
```

and identified the likely root cause as:

```text
Simulated application failure for incident-response testing.
```

The response also referenced the actual CloudWatch RuntimeError and traceback evidence.

### Why This Matters

The AI layer was not operating from a generic prompt.

It was reasoning over evidence produced by the monitored AWS workload.

That distinction is central to the design of the project.

---

## Phase 10 — AI Failure Isolation

Adding Bedrock introduced a new dependency into the Incident Analyzer.

The architecture was intentionally designed so that failure of the AI layer would not cause loss of the underlying incident.

If AI processing succeeds:

```text
analysis_status = SUCCESS
```

and the AI analysis is attached to the incident.

If Bedrock inference or response parsing fails:

```text
analysis_status = FAILED
analysis_error = <error>
```

The original incident is still preserved.

### Engineering Principle

AI should improve an operational workflow without becoming the workflow's single point of failure.

This means incident preservation is treated as more important than successful AI enrichment.
---

## Phase 11 — Lambda Timeout Tuning

The Incident Analyzer originally used a 10-second timeout.

That was sufficient when the function only parsed events and stored data.

After adding:

```text
CloudWatch log retrieval
Amazon Bedrock inference
JSON parsing
DynamoDB persistence
```

the execution path became longer and depended on multiple AWS service calls.

The timeout was increased to:

```text
30 seconds
```

### Reasoning

The goal was to provide enough headroom for network and service latency without making the function effectively unbounded.

This was a reliability adjustment based on the actual workload rather than an arbitrary configuration change.

---

## Phase 12 — Least-Privilege IAM

As the Incident Analyzer gained new responsibilities, IAM permissions were expanded carefully.

The required actions were:

### CloudWatch Logs

```text
logs:FilterLogEvents
```

Used to retrieve operational evidence from the test application's log group.

### Amazon Bedrock

```text
bedrock:InvokeModel
```

Used to invoke the configured Amazon Nova Pro model.

### DynamoDB

```text
dynamodb:PutItem
```

Used to persist the completed incident record.

Where supported, permissions were scoped to the specific resources used by the project.

Broad permissions such as:

```text
logs:*
bedrock:*
dynamodb:*
```

were intentionally avoided.

### Lesson Learned

Adding functionality should not automatically mean adding broad access.

Each new capability should be mapped to the minimum action and resource scope required.

---

## Phase 13 — Final End-to-End Validation

The completed system was tested from controlled failure generation through AI analysis and persistent storage.

The final flow was:

```text
Controlled Lambda Failure
        ↓
CloudWatch Error Detection
        ↓
Alarm OK → ALARM
        ↓
EventBridge Routing
        ↓
Incident Analyzer Invocation
        ↓
CloudWatch Evidence Retrieval
        ↓
Amazon Bedrock Analysis
        ↓
Structured Root-Cause Intelligence
        ↓
DynamoDB Persistence
        ↓
Successful Record Read-Back
```

The Incident Analyzer logs showed:

```text
INCIDENT_EVENT
LOG_EVIDENCE
BEDROCK_ANALYSIS
INCIDENT_STORED
```

The Bedrock output contained:

```text
incident_summary
severity
likely_root_cause
evidence
recommended_actions
confidence
```

The final test returned:

```text
severity = LOW
confidence = HIGH
```

with the likely root cause correctly identified as the intentionally simulated application failure.

---

## Phase 14 — DynamoDB Read-Back Verification

The final incident was queried directly from DynamoDB.

The stored record contained both the original CloudWatch alarm metadata and the AI-generated analysis.

The record confirmed:

```text
analysis_status = SUCCESS
severity        = LOW
confidence      = HIGH
```

This proved that the AI result was not only emitted to logs.

It became part of the durable incident record.

---

## Phase 15 — Terraform State Verification

After the successful end-to-end test, Terraform was run again to compare the deployed AWS environment against the Infrastructure as Code configuration.

The final result was:

```text
No changes. Your infrastructure matches the configuration.
```

This confirmed:

```text
no pending infrastructure changes
no unintended drift
deployed state matches Terraform
```

### Why This Matters

A successful application test does not automatically prove the infrastructure is in a clean managed state.

The final Terraform plan provided an additional validation layer.

---

## Key Lessons Learned

This project reinforced several engineering principles:

- validate individual components before integrating them
- create controlled failures for repeatable testing
- retrieve evidence before asking AI to reason
- separate detection from analysis
- prefer event-driven routing over polling where appropriate
- preserve incidents even if AI enrichment fails
- use least-privilege IAM
- review Terraform plans before applying infrastructure changes
- understand CloudWatch metric and alarm evaluation latency
- persist operational state instead of relying only on logs
- tune timeouts based on the real execution path
- verify infrastructure state after deployment

---

## Final Outcome

The completed project is an event-driven AI incident-response system on AWS that detects Lambda failures, retrieves operational evidence, uses Amazon Bedrock to generate structured root-cause analysis and remediation guidance, and persists the complete incident record in DynamoDB — all provisioned with Terraform and least-privilege IAM.

The project demonstrates both the ability to build cloud and AI components and the operational discipline required to monitor, secure, test, troubleshoot, and manage them.
