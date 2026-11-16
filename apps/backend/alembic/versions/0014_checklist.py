"""logistics: shared trip checklist

Revision ID: 0014_checklist
Revises: 0013_navigation
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0014_checklist"
down_revision = "0013_navigation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "checklist_items",
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
        sa.Column("title", sa.String(160), nullable=False),
        sa.Column(
            "category", sa.String(16), nullable=False, server_default="packing"
        ),
        sa.Column("qty", sa.Integer(), nullable=False, server_default="1"),
        sa.Column(
            "created_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "assigned_to",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "done", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
        sa.Column(
            "done_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "category in ('packing','supplies','food','gear','todo','other')",
            name="checklist_items_category_check",
        ),
        sa.CheckConstraint("qty >= 1", name="checklist_items_qty_check"),
    )
    op.create_index("ix_checklist_items_trip", "checklist_items", ["trip_id"])


def downgrade() -> None:
    op.drop_index("ix_checklist_items_trip", table_name="checklist_items")
    op.drop_table("checklist_items")
