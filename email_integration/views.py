from rest_framework.response import Response
from rest_framework.views import APIView

from .services import create_inbox


class CreateInboxView(APIView):
    def post(self, request):
        email_address = request.data.get("email")
        if not email_address:
            return Response({"error": "email is required"}, status=400)
        result = create_inbox(email_address)
        return Response(result)
