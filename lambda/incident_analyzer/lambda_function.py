import json
import os
import uuid
from datetime import datetime, timedelta, timezone

import boto3


TABLE_NAME = os.environ["INCIDENT_TABLE_NAME"]
SOURCE_LOG_GROUP = os.environ["SOURCE_LOG_GROUP"]
BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]

dynamodb = boto3.resource("dynamodb")
logs_client = boto3.client("logs")
bedrock_client = boto3.client("bedrock-runtime")

incident_table = dynamodb.Table(TABLE_NAME)


def clean_json_response(text):
    """
    Removes Markdown code fences if the model returns them,
    then parses the remaining JSON.
    """
    cleaned = text.strip()

    if cleaned.startswith("```json"):
        cleaned = cleaned[7:]
    elif cleaned.startswith("```"):
        cleaned = cleaned[3:]

    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]

    return json.loads(cleaned.strip())


def get_log_evidence(timestamp):
    """
    Retrieves recent CloudWatch log evidence surrounding the alarm.
    """

    try:
        event_time = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except Exception:
        event_time = datetime.now(timezone.utc)

    start_time = int(
        (event_time - timedelta(minutes=5)).timestamp() * 1000
    )

    end_time = int(
        (event_time + timedelta(minutes=2)).timestamp() * 1000
    )

    response = logs_client.filter_log_events(
        logGroupName=SOURCE_LOG_GROUP,
        startTime=start_time,
        endTime=end_time,
        limit=100
    )

    messages = []

    for log_event in response.get("events", []):
        message = log_event.get("message", "")

        if any(
            keyword in message
            for keyword in [
                "ERROR",
                "RuntimeError",
                "Exception",
                "Traceback"
            ]
        ):
            messages.append(message)

    evidence = "\n".join(messages)

    return evidence[:8000] if evidence else \
        "No matching error log evidence found."


def analyze_with_bedrock(incident, log_evidence):
    """
    Sends operational evidence to Amazon Bedrock and returns
    structured AI incident analysis.
    """

    prompt = f"""
You are an AWS incident-response assistant.

Analyze only the evidence provided below.
Do not invent facts.

Return ONLY valid JSON with exactly these fields:

incident_summary
severity
likely_root_cause
evidence
recommended_actions
confidence

Alarm:
{json.dumps(incident, indent=2)}

CloudWatch log evidence:
{log_evidence}
"""

    response = bedrock_client.converse(
        modelId=BEDROCK_MODEL_ID,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "text": prompt
                    }
                ]
            }
        ],
        inferenceConfig={
            "maxTokens": 700,
            "temperature": 0
        }
    )

    model_text = (
        response["output"]["message"]["content"][0]["text"]
    )

    return clean_json_response(model_text)


def lambda_handler(event, context):
    """
    Receives CloudWatch alarm events, gathers operational evidence,
    generates AI-assisted incident analysis, and stores the incident.
    """

    detail = event.get("detail", {})
    state = detail.get("state", {})
    previous_state = detail.get("previousState", {})

    incident_id = event.get("id") or str(uuid.uuid4())

    timestamp = state.get(
        "timestamp",
        event.get(
            "time",
            datetime.now(timezone.utc).isoformat()
        )
    )

    incident = {
        "incident_id": incident_id,
        "alarm_name": detail.get("alarmName", "unknown"),
        "current_state": state.get("value", "unknown"),
        "previous_state": previous_state.get(
            "value",
            "unknown"
        ),
        "reason": state.get(
            "reason",
            "No reason provided"
        ),
        "timestamp": timestamp,
        "region": event.get("region", "unknown"),
        "source": event.get("source", "unknown")
    }

    print("INCIDENT_EVENT:")
    print(json.dumps(incident, indent=2))

    log_evidence = get_log_evidence(timestamp)

    print("LOG_EVIDENCE:")
    print(log_evidence)

    try:
        ai_analysis = analyze_with_bedrock(
            incident,
            log_evidence
        )

        incident["analysis_status"] = "SUCCESS"
        incident["ai_analysis"] = ai_analysis

        print("BEDROCK_ANALYSIS:")
        print(json.dumps(ai_analysis, indent=2))

    except Exception as error:
        incident["analysis_status"] = "FAILED"
        incident["analysis_error"] = str(error)

        print(f"BEDROCK_ANALYSIS_FAILED: {error}")

    incident_table.put_item(Item=incident)

    print(f"INCIDENT_STORED: {incident_id}")

    return {
        "statusCode": 200,
        "body": json.dumps(incident)
    }
