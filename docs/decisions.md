# AI Incident Intelligence — Architecture Decision Log

## Purpose

This document records the major engineering decisions made during the AI Incident Intelligence project and the reasoning behind them.

---

## Decision 1 — Use Event-Driven Routing Instead of Polling

### Decision

Use Amazon EventBridge to respond to CloudWatch alarm state changes.

### Reasoning

The Incident Analyzer only needs to execute when a meaningful operational event occurs.

Polling CloudWatch continuously would introduce unnecessary executions and tighter coupling.

### Result

The architecture became:

```text
CloudWatch Alarm
      ↓
EventBridge
      ↓
Incident Analyzer
```

This reduced unnecessary compute and created a loosely coupled event-driven workflow.

---

## Decision 2 — Retrieve Operational Evidence Before AI Analysis

### Decision

Retrieve CloudWatch logs before invoking Amazon Bedrock.

### Reasoning

An alarm indicates that a threshold was crossed, but it does not necessarily identify the root cause.

Providing actual error messages and traceback evidence gives the model stronger context.

### Result

The AI analysis is grounded in observed workload behavior rather than only alarm metadata.

---

## Decision 3 — Keep AI Outside the Critical Persistence Path

### Decision

Preserve incidents even if Amazon Bedrock fails.

### Reasoning

The AI model should enrich incident response, not determine whether an incident can be recorded.

### Implementation

Successful AI processing:

```text
analysis_status = SUCCESS
```

Failed AI processing:

```text
analysis_status = FAILED
analysis_error = <error>
```

The underlying incident is persisted in either case.

### Result

Amazon Bedrock does not become a single point of failure.

---

## Decision 4 — Use DynamoDB for Incident Persistence

### Decision

Use Amazon DynamoDB to store completed incident records.

### Reasoning

The workload is serverless and event-driven, and each incident is naturally represented as a structured record.

DynamoDB provides:

- serverless operation
- simple key-based retrieval
- managed scalability
- low operational overhead
- direct Lambda integration

### Result

Incident records remain available after Lambda execution and can support future analytics or automation.

---

## Decision 5 — Use Controlled Failure Injection

### Decision

Build a dedicated failure path into the test Lambda.

### Reasoning

Waiting for unpredictable failures would make testing inconsistent.

Controlled failure injection makes the pipeline deterministic and repeatable.

### Result

The entire system can be validated on demand:

```text
Controlled Failure
      ↓
Monitoring
      ↓
Routing
      ↓
Analysis
      ↓
Persistence
```
---

## Decision 6 — Use Least-Privilege IAM

### Decision

Grant only the AWS API permissions required by each workload.

### Required Actions

```text
dynamodb:PutItem
logs:FilterLogEvents
bedrock:InvokeModel
```

### Reasoning

Broad permissions would make implementation faster, but they would also increase unnecessary access and blast radius.

### Result

The Incident Analyzer receives only the permissions required for its responsibilities, with resource scope restricted where supported.

---

## Decision 7 — Validate Bedrock Independently Before Integration

### Decision

Test Amazon Nova Pro independently before adding it to the Incident Analyzer.

### Reasoning

This isolated several external dependency questions:

- model availability
- AWS authentication
- region configuration
- API invocation
- expected response structure

### Result

Bedrock integration began only after the model could be invoked successfully on its own.

This reduced troubleshooting complexity during the final integration.

---

## Decision 8 — Parse AI Output Defensively

### Decision

Normalize and validate the model response before parsing it as JSON.

### Reasoning

Even when structured JSON is requested, generative AI responses may include additional formatting.

Downstream automation should not depend on perfect presentation formatting from the model.

### Result

The Incident Analyzer defensively removes optional Markdown formatting and validates the structured response before using it.

---

## Decision 9 — Increase the Analyzer Timeout Based on Actual Workload

### Decision

Increase the Incident Analyzer timeout from:

```text
10 seconds
```

to:

```text
30 seconds
```

### Reasoning

The analyzer's execution path expanded to include:

```text
CloudWatch log retrieval
        ↓
Amazon Bedrock inference
        ↓
JSON parsing
        ↓
DynamoDB persistence
```

The original timeout no longer reflected the function's actual responsibilities.

### Result

The Lambda has sufficient execution headroom for AWS service calls while remaining bounded.

---

## Decision 10 — Use Saved Terraform Plans for Controlled Deployment

### Decision

Save and review Terraform plans before applying infrastructure changes.

### Reasoning

The plan provides visibility into:

- resources being created
- resources being modified
- resources being destroyed
- replacement risk
- IAM changes
- expected blast radius

### Result

Infrastructure changes can be reviewed before AWS resources are modified.

The final AI integration deployment showed:

```text
1 added
1 changed
0 destroyed
```

This matched the expected change set.

---

## Decision 11 — Verify Zero Drift Before Completion

### Decision

Run a final:

```bash
terraform plan
```

after end-to-end system validation.

### Reasoning

A successful application test proves runtime behavior.

It does not prove that the deployed infrastructure still matches the Infrastructure as Code definition.

### Result

Terraform returned:

```text
No changes. Your infrastructure matches the configuration.
```

This confirmed that the AWS environment matched the intended Terraform state.

---

## Engineering Philosophy

The project followed several consistent engineering principles:

```text
Evidence before assumptions

Root cause before changes

Observability before speculation

Least privilege before convenience

Small blast radius before speed

AI enrichment without AI dependency

Repeatable testing before confidence

Infrastructure validation before completion
```

These decisions were made to create a system that is not only functional, but also observable, secure, testable, recoverable, and operationally reliable.

The goal was to demonstrate the ability to build AI-enabled cloud infrastructure and also manage the engineering concerns surrounding that infrastructure.
