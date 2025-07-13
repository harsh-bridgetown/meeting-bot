from django.db import models


class EmailEvent(models.Model):
    message_id = models.CharField(max_length=512, unique=True)
    from_address = models.CharField(max_length=512)
    subject = models.CharField(max_length=512, blank=True)
    received_at = models.DateTimeField(auto_now_add=True)
    attachments = models.JSONField(default=list, blank=True)
    event_data = models.JSONField(null=True, blank=True)

    def __str__(self):
        return self.subject or self.message_id
