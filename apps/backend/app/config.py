"""Runtime configuration loaded from environment / .env."""

from functools import lru_cache
from typing import List

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


def _split_csv(value: str) -> List[str]:
    return [v.strip() for v in value.split(",") if v.strip()]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    environment: str = "local"
    debug: bool = True

    api_host: str = "0.0.0.0"
    api_port: int = 8000
    # Stored as a raw CSV string and exposed as a list via the `cors_origins`
    # property below. Keeping the field a plain `str` stops pydantic-settings
    # from trying to JSON-decode the .env value (e.g. "http://a,http://b"),
    # which would otherwise raise a SettingsError before any validator runs.
    cors_origins_raw: str = Field(default="*", validation_alias="CORS_ORIGINS")

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

    # Maps providers — at least one of these should be configured.
    # MAPS_PROVIDER picks the default; MAPS_FALLBACK_PROVIDERS chains
    # alternates that get tried in order if the default fails.
    maps_provider: str = ""
    maps_fallback_providers_raw: str = Field(
        default="", validation_alias="MAPS_FALLBACK_PROVIDERS"
    )

    mapbox_server_token: str = ""
    google_maps_api_key: str = ""
    mappls_client_id: str = ""
    mappls_client_secret: str = ""
    mappls_rest_key: str = ""  # Some Mappls accounts use a REST key in the path
    here_api_key: str = ""
    tomtom_api_key: str = ""
    osrm_base_url: str = "https://router.project-osrm.org"

    livekit_url: str = ""
    livekit_api_key: str = ""
    livekit_api_secret: str = ""

    fcm_service_account_json: str = ""

    @property
    def cors_origins(self) -> List[str]:
        return _split_csv(self.cors_origins_raw)

    @property
    def maps_fallback_providers(self) -> List[str]:
        return _split_csv(self.maps_fallback_providers_raw)

    @property
    def otp_dev_mode(self) -> bool:
        """When MSG91 is unset we return OTPs in the API response (local dev only)."""
        return not self.msg91_auth_key


@lru_cache
def get_settings() -> Settings:
    return Settings()
