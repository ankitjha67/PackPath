"""emergency contacts (per user)

Revision ID: 0012_emergency_contacts
Revises: 0011_message_reactions
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0012_emergency_contacts"
down_revision = "0011_message_reactions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "emergency_contacts",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("phone", sa.String(30), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_emergency_contacts_user", "emergency_contacts", ["user_id"]
    )


def downgrade() -> None:
    op.drop_table("emergency_contacts")
