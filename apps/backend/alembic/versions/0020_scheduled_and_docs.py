"""scheduled announcements + document vault

Revision ID: 0020_scheduled_and_docs
Revises: 0019_marshall_ops
Create Date: 2026-11-18
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0020_scheduled_and_docs"
down_revision = "0019_marshall_ops"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "scheduled_announcements",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "trip_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "created_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("send_at", sa.TIMESTAMP(timezone=True), nullable=False),
        sa.Column(
            "sent", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_sched_due", "scheduled_announcements", ["sent", "send_at"]
    )
    op.create_table(
        "trip_documents",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "trip_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "added_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("title", sa.String(length=120), nullable=False),
        sa.Column("kind", sa.String(length=10), nullable=False),
        sa.Column("url", sa.String(length=1000), nullable=True),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint("kind in ('link','note')", name="trip_documents_kind"),
    )
    op.create_index("ix_docs_trip", "trip_documents", ["trip_id"])


def downgrade() -> None:
    op.drop_index("ix_docs_trip", table_name="trip_documents")
    op.drop_table("trip_documents")
    op.drop_index("ix_sched_due", table_name="scheduled_announcements")
    op.drop_table("scheduled_announcements")
