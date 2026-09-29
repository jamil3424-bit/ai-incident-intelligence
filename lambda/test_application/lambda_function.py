import json


def lambda_handler(event, context):
    """
    Test application used to generate controlled incidents
    for the AI Incident Intelligence project.
    """

    simulate_failure = event.get("simulate_failure", False)

    if simulate_failure:
        raise RuntimeError(
            "Simulated application failure for incident-response testing."
        )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Application is healthy",
            "simulate_failure": False
        })
    }
