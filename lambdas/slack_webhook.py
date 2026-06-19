import json
import logging
import os
import time
import urllib.error
import urllib.request

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SLACK_POST_MESSAGE_URL = "https://slack.com/api/chat.postMessage"


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


def build_attachment_for_record(sns, stack_name):
    """Build the Slack attachment for an SNS record. Transport-agnostic."""
    subject = sns.get("Subject", "")
    message = sns.get("Message", "")

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

    return create_attachment(title, text, color, stack_name)


def post_via_webhook(webhook_url, stack_name, attachment):
    """Post to a Slack Incoming Webhook. Failures surface as a non-2xx HTTP status."""
    payload = {
        "username": stack_name,
        "icon_url": "https://runs-on.com/logo.png",
        "attachments": [attachment],
    }
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        webhook_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        logger.info("Sent alert to Slack webhook with status %s", response.status)


def post_via_bot(token, channel, attachment):
    """Post via chat.postMessage.

    chat.postMessage returns HTTP 200 even on failure, signalling errors with
    {"ok": false, "error": "..."} in the body, so we must inspect the body.
    """
    payload = {
        "channel": channel,
        "attachments": [attachment],
    }
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        SLACK_POST_MESSAGE_URL,
        data=data,
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {token}",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        raw = response.read().decode("utf-8")

    result = json.loads(raw)
    if not result.get("ok", False):
        raise RuntimeError(
            f"chat.postMessage failed: {result.get('error', 'unknown error')}"
        )
    logger.info("Sent alert to Slack channel %s", channel)


def handler(event, context):
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL", "")
    bot_token = os.environ.get("SLACK_BOT_TOKEN", "")
    channel_id = os.environ.get("SLACK_CHANNEL_ID", "")
    stack_name = os.environ.get("STACK_NAME", "RunsOn")

    # Bot token takes precedence over the webhook when both are configured.
    use_bot = bool(bot_token and channel_id)
    if not use_bot and not webhook_url:
        logger.error(
            "No Slack delivery method configured (webhook URL or bot token + channel)"
        )
        return {"statusCode": 500, "body": "Slack alerting is not configured"}

    for record in event.get("Records", []):
        attachment = build_attachment_for_record(record.get("Sns", {}), stack_name)

        try:
            if use_bot:
                post_via_bot(bot_token, channel_id, attachment)
            else:
                post_via_webhook(webhook_url, stack_name, attachment)
        except urllib.error.HTTPError as error:
            logger.error(
                "Failed to send alert to Slack: HTTP %s %s", error.code, error.reason
            )
        except Exception as error:  # noqa: BLE001
            logger.exception("Unexpected error sending alert to Slack: %s", error)

    return {"statusCode": 200, "body": "Processed SNS records"}
