"""Runtime configuration loaded from environment / .env."""

from functools import lru_cache
from typing import List

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    environment: str = "local"
    debug: bool = True

    api_host: str = "0.0.0.0"
    api_port: int = 8000
    cors_origins: List[str] = Field(default_factory=lambda: ["*"])

    database_url: str = "postgresql+asyncpg://packpath:packpath@localhost:5432/packpath"
    redis_url: str = "redis://localhost:6379/0"

    jwt_secret: str = "change-me-in-prod"
    jwt_access_ttl_minutes: int = 15
    jwt_refresh_ttl_days: int = 30
    jwt_algorithm: str = "HS256"

    otp_ttl_seconds: int = 300
    otp_length: int = 6
    msg91_auth_key: str = ""
    msg91_template_id: str = ""
    msg91_sender_id: str = "PACKPT"

    mapbox_server_token: str = ""

    livekit_url: str = ""
    livekit_api_key: str = ""
    livekit_api_secret: str = ""

    fcm_service_account_json: str = ""

    @field_validator("cors_origins", mode="before")
    @classmethod
    def split_csv(cls, value):
        if isinstance(value, str):
            return [v.strip() for v in value.split(",") if v.strip()]
        return value

    @property
    def otp_dev_mode(self) -> bool:
        """When MSG91 is unset we return OTPs in the API response (local dev only)."""
        return not self.msg91_auth_key


@lru_cache
def get_settings() -> Settings:
    return Settings()
