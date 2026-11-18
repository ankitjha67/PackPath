"""OTP SMS delivery via MSG91.

Dev mode (no MSG91 auth key) returns the OTP in the API response instead of
sending an SMS — see `Settings.otp_dev_mode`. When a key is configured this
sends the generated code through MSG91's v5 OTP API, passing our own `otp`
value and the account's template.
"""

from __future__ import annotations

import httpx
from loguru import logger

from ..config import get_settings

_OTP_URL = "https://control.msg91.com/api/v5/otp"


class SmsDeliveryError(RuntimeError):
    """MSG91 rejected the send or was unreachable."""


async def send_otp_sms(phone: str, code: str) -> None:
    """Send `code` to `phone` via MSG91. Raises SmsDeliveryError on failure.

    No-op when MSG91 is not configured (dev mode handles delivery elsewhere).
    """
    settings = get_settings()
    if not settings.msg91_auth_key:
        return
    # MSG91 expects the number with country code and no leading '+'.
    mobile = phone.lstrip("+").replace(" ", "")
    params = {
        "template_id": settings.msg91_template_id,
        "mobile": mobile,
        "otp": code,
    }
    if settings.msg91_sender_id:
        params["sender"] = settings.msg91_sender_id
    headers = {"authkey": settings.msg91_auth_key, "accept": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.post(_OTP_URL, params=params, headers=headers)
    except httpx.HTTPError as exc:  # network/timeout
        logger.warning("MSG91 OTP send failed (network): {}", exc)
        raise SmsDeliveryError("could not reach the SMS provider") from exc
    if r.status_code != 200:
        logger.warning("MSG91 OTP send failed {}: {}", r.status_code, r.text[:200])
        raise SmsDeliveryError(f"SMS provider returned {r.status_code}")
    body = r.json() if r.headers.get("content-type", "").startswith(
        "application/json"
    ) else {}
    if str(body.get("type", "")).lower() == "error":
        logger.warning("MSG91 OTP send rejected: {}", body.get("message"))
        raise SmsDeliveryError("SMS provider rejected the request")
