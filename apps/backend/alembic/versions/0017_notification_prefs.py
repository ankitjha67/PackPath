"""push & infra: notification preferences

Revision ID: 0017_notification_prefs
Revises: 0016_user_preferences
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0017_notification_prefs"
down_revision = "0016_user_preferences"
branch_labels = None
depends_on = None

_BOOL_COLS = (
    "enabled",
    "announcements",
    "nudges",
    "detours",
    "hazards",
    "chat",
    "checklist",
)


def upgrade() -> None:
    op.create_table(
        "notification_preferences",
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        *[
            sa.Column(c, sa.Boolean(), nullable=False, server_default=sa.text("true"))
            for c in _BOOL_COLS
        ],
        sa.Column("quiet_start", sa.SmallInteger(), nullable=True),
        sa.Column("quiet_end", sa.SmallInteger(), nullable=True),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("notification_preferences")
