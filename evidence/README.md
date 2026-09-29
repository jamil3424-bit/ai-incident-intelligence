# AI Incident Intelligence — Validation Evidence

This directory contains redacted validation evidence from the completed AWS AI incident-response system.

## Evidence Captured

### 1. Terraform Infrastructure Validation

Evidence showing:

- Terraform configuration validated successfully
- deployed infrastructure matched configuration
- final plan returned zero drift

Expected result:

```text
No changes. Your infrastructure matches the configuration.
```

### 2. CloudWatch Alarm Detection

Evidence showing the test application's CloudWatch alarm transitioning:

```text
OK → ALARM
```

after a controlled Lambda failure.

### 3. Incident Analyzer Execution

CloudWatch logs demonstrating the analyzer workflow:

```text
INCIDENT_EVENT
LOG_EVIDENCE
BEDROCK_ANALYSIS
INCIDENT_STORED
```

### 4. Operational Log Evidence

Evidence retrieved from the failed Lambda including:

```text
RuntimeError
Traceback
Simulated application failure for incident-response testing.
```

### 5. Amazon Bedrock Analysis

Evidence showing Amazon Nova Pro produced structured incident intelligence including:

```text
incident_summary
severity
likely_root_cause
evidence
recommended_actions
confidence
```

Validated test result:

```text
severity = LOW
confidence = HIGH
```
### 6. DynamoDB Persistence

Evidence showing the complete incident was persisted in:

```text
ai-incident-records
```

The stored item included:

```text
analysis_status = SUCCESS
```

along with the structured AI analysis.

The persisted record also contained:

```text
incident_id
alarm_name
timestamp
source
current_state
previous_state
reason
region
incident_summary
severity
likely_root_cause
evidence
recommended_actions
confidence
```

This proves the AI result became part of the durable incident record rather than existing only in Lambda logs.

---

## Redaction Standard

Before screenshots are committed to GitHub or posted publicly, redact:

- AWS account IDs
- ARNs containing account identifiers
- resource IDs where appropriate
- IP addresses
- email addresses
- tokens
- credentials
- secrets
- private endpoints

No secrets or credentials should be stored in this repository.

When evidence is included publicly, screenshots should preserve enough context to prove the system worked while removing unnecessary identifying information.
