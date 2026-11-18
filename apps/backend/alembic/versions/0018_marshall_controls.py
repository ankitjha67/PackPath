"""marshall controls: stop metadata + route lock

Revision ID: 0018_marshall_controls
Revises: 0017_notification_prefs
Create Date: 2026-11-18
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0018_marshall_controls"
down_revision = "0017_notification_prefs"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "waypoints",
        sa.Column("category", sa.String(length=20), nullable=True),
    )
    op.add_column(
        "waypoints",
        sa.Column("notes", sa.String(length=500), nullable=True),
    )
    op.add_column(
        "waypoints",
        sa.Column(
            "assignee_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.add_column(
        "trips",
        sa.Column(
            "route_locked",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("trips", "route_locked")
    op.drop_column("waypoints", "assignee_id")
    op.drop_column("waypoints", "notes")
    op.drop_column("waypoints", "category")
