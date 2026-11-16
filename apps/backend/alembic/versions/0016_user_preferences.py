"""personalization: user preferences

Revision ID: 0016_user_preferences
Revises: 0015_user_badges
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0016_user_preferences"
down_revision = "0015_user_badges"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_preferences",
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("units", sa.String(10), nullable=False, server_default="metric"),
        sa.Column("temp_unit", sa.String(1), nullable=False, server_default="c"),
        sa.Column(
            "map_style", sa.String(20), nullable=False, server_default="mapbox"
        ),
        sa.Column(
            "vehicle_type", sa.String(20), nullable=False, server_default="hatchback"
        ),
        sa.Column("mileage_kmpl", sa.Float(), nullable=True),
        sa.Column(
            "share_location_default",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "units in ('metric','imperial')", name="user_prefs_units_check"
        ),
        sa.CheckConstraint("temp_unit in ('c','f')", name="user_prefs_temp_check"),
    )


def downgrade() -> None:
    op.drop_table("user_preferences")
