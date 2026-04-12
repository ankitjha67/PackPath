from pydantic import BaseModel, Field


class OtpRequest(BaseModel):
    phone: str = Field(min_length=8, max_length=20)


class OtpRequestResponse(BaseModel):
    sent: bool
    # Returned only when running with no MSG91 key (local dev).
    debug_otp: str | None = None


class OtpVerify(BaseModel):
    phone: str = Field(min_length=8, max_length=20)
    code: str = Field(min_length=4, max_length=8)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str
