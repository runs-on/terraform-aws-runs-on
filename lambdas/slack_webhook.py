import json
import logging
import os
import time
import urllib.error
import urllib.request

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def get_alert_color(subject, state=None):
    """Determine the color for a Slack alert based on content."""
    if state:
        state_lower = state.lower()
        if state_lower == "alarm":
            return "danger"
        if state_lower == "ok":
            return "good"
        if state_lower == "insufficient_data":
            return "warning"

    if subject:
        subject_lower = subject.lower()
        if any(word in subject_lower for word in ["error", "fail", "❌"]):
            return "danger"
        if any(word in subject_lower for word in ["warn", "⚠️", "unable"]):
            return "warning"
        if any(word in subject_lower for word in ["success", "✅", "complete"]):
            return "good"

    return "#439FE0"  # Default blue color


def create_attachment(title, text, color, stack_name):
    """Create a Slack attachment."""
    return {
        "color": color,
        "title": title,
        "text": text,
        "footer": stack_name,
        "ts": int(time.time()),
    }


def handler(event, context):
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    stack_name = os.environ.get("STACK_NAME", "RunsOn")

    if not webhook_url:
        logger.error("Slack webhook URL is not configured")
        return {"statusCode": 500, "body": "Slack webhook URL is not configured"}

    records = event.get("Records", [])
    for record in records:
        sns = record.get("Sns", {})
        subject = sns.get("Subject", "")
        message = sns.get("Message", "")

        payload = {
            "username": stack_name,
            "icon_url": "https://runs-on.com/logo.png",
        }

        try:
            alarm_data = json.loads(message)
            if "AlarmName" in alarm_data:
                state = alarm_data.get("NewStateValue", "UNKNOWN")
                state_emoji = {
                    "ALARM": ":rotating_light:",
                    "OK": ":white_check_mark:",
                    "INSUFFICIENT_DATA": ":warning:",
                }.get(state, ":question:")
                title = f"{state_emoji} CloudWatch Alarm: {state}"
                text = f"*Alarm:* {alarm_data.get('AlarmName', 'N/A')}\n*Reason:* {alarm_data.get('NewStateReason', 'N/A')}"
                color = get_alert_color(None, state)
            else:
                title = subject if subject else "JSON Message"
                text = f"```\n{json.dumps(alarm_data, indent=2)}\n```"
                color = get_alert_color(subject)
        except (json.JSONDecodeError, TypeError):
            title = subject if subject else "Alert"
            text = message
            color = get_alert_color(subject)

        payload["attachments"] = [create_attachment(title, text, color, stack_name)]

        data = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            webhook_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                logger.info("Sent alert to Slack with status %s", response.status)
        except urllib.error.HTTPError as error:
            logger.error(
                "Failed to send alert to Slack: HTTP %s %s", error.code, error.reason
            )
        except Exception as error:  # noqa: BLE001
            logger.exception("Unexpected error sending alert to Slack: %s", error)

    return {"statusCode": 200, "body": "Processed SNS records"}
