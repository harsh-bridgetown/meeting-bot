import logging
import os
from email import policy
from email.parser import BytesParser
from io import BytesIO

import boto3
from ics import Calendar

from bots.bots_api_utils import BotCreationSource, create_bot
from bots.models import Project

from .models import EmailEvent

logger = logging.getLogger(__name__)


def create_inbox(email_address: str):
    client = boto3.client("ses", region_name=os.getenv("AWS_REGION"))
    client.verify_email_identity(EmailAddress=email_address)
    return {"status": "verification_started"}


def process_email(raw_email: bytes, project: Project):
    msg = BytesParser(policy=policy.default).parsebytes(raw_email)
    message_id = msg.get("Message-ID")
    from_address = msg.get("From")
    subject = msg.get("Subject", "")

    attachments = []
    event_data = None

    s3_client = boto3.client("s3", endpoint_url=os.getenv("AWS_ENDPOINT_URL"))
    bucket = os.getenv("ATTACHMENT_BUCKET", "attachments")

    for part in msg.iter_attachments():
        filename = part.get_filename()
        if not filename:
            continue
        content = part.get_payload(decode=True)
        if filename.lower().endswith((".pdf", ".docx", ".xlsx")):
            key = f"{message_id}/{filename}"
            s3_client.put_object(Bucket=bucket, Key=key, Body=content)
            attachments.append({"s3_key": key, "filename": filename})
        elif filename.lower().endswith(".ics"):
            cal = Calendar(BytesIO(content).read().decode())
            for event in cal.events:
                meeting_url = event.url or ""
                start = event.begin.datetime
                data = {
                    "meeting_url": meeting_url,
                    "bot_name": subject or "Email Bot",
                    "join_at": start.isoformat() if start else None,
                }
                bot, error = create_bot(data, BotCreationSource.API, project)
                if error:
                    logger.error("Failed to create bot: %s", error)
                else:
                    event_data = {
                        "bot_id": bot.object_id,
                        "join_at": data["join_at"],
                        "meeting_url": meeting_url,
                    }
    EmailEvent.objects.create(
        message_id=message_id,
        from_address=from_address,
        subject=subject,
        attachments=attachments,
        event_data=event_data,
    )
