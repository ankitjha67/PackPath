"""Reddit-style display names and deterministic avatars for users.

Users authenticate by phone only, so without a friendly identity every
surface (member list, chat, expenses) falls back to a raw UUID. We mint a
``Adjective_Animal_1234`` handle at sign-up and a deterministic avatar URL
seeded by that handle, so the same user always renders the same avatar.
"""

from __future__ import annotations

import secrets
from urllib.parse import quote

_ADJECTIVES = [
    "Sleepy", "Brave", "Clever", "Cosmic", "Crimson", "Dapper", "Eager",
    "Fuzzy", "Gentle", "Golden", "Happy", "Humble", "Jolly", "Lucky",
    "Mellow", "Mighty", "Nimble", "Plucky", "Quiet", "Rapid", "Rowdy",
    "Rustic", "Shiny", "Silent", "Silly", "Snappy", "Sneaky", "Spicy",
    "Stormy", "Sunny", "Swift", "Tidy", "Vivid", "Witty", "Zesty",
    "Breezy", "Curious", "Daring", "Frosty", "Glowing", "Noble", "Wandering",
]

_ANIMALS = [
    "Panda", "Otter", "Falcon", "Badger", "Beaver", "Bison", "Bobcat",
    "Cheetah", "Cobra", "Coyote", "Dolphin", "Eagle", "Ferret", "Fox",
    "Gecko", "Heron", "Ibex", "Jaguar", "Koala", "Lemur", "Lynx",
    "Marmot", "Moose", "Narwhal", "Ocelot", "Panther", "Puffin", "Quokka",
    "Raccoon", "Raven", "Seal", "Sparrow", "Stingray", "Tapir", "Toucan",
    "Walrus", "Weasel", "Wombat", "Yak", "Wolf", "Mongoose", "Pangolin",
]

# DiceBear is a deterministic avatar service: the same seed always yields the
# same image. "bottts" gives friendly robot heads. Clients fall back to
# initials when the network image can't load, so this URL is best-effort.
_AVATAR_STYLE = "bottts"


def generate_display_name() -> str:
    """Return a fresh ``Adjective_Animal_1234`` handle."""
    adjective = secrets.choice(_ADJECTIVES)
    animal = secrets.choice(_ANIMALS)
    number = secrets.randbelow(9000) + 1000  # 1000–9999
    return f"{adjective}_{animal}_{number}"


def avatar_url_for(seed: str) -> str:
    """Deterministic avatar URL for ``seed`` (typically the display name)."""
    return f"https://api.dicebear.com/9.x/{_AVATAR_STYLE}/png?seed={quote(seed)}"


def new_identity() -> tuple[str, str]:
    """Return a ``(display_name, avatar_url)`` pair for a new user."""
    name = generate_display_name()
    return name, avatar_url_for(name)
