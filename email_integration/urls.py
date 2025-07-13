from django.urls import path

from .views import CreateInboxView

urlpatterns = [
    path("create/", CreateInboxView.as_view(), name="create-inbox"),
]
