"""Import all models so Alembic / SQLAlchemy can discover them."""

from .device import Device  # noqa: F401
from .message import Message  # noqa: F401
from .trip import Trip, TripMember  # noqa: F401
from .user import User  # noqa: F401
from .waypoint import Waypoint  # noqa: F401
