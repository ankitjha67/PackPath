"""chat message reactions (emoji)

Revision ID: 0011_message_reactions
Revises: 0010_establishments
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0011_message_reactions"
down_revision = "0010_establishments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "message_reactions",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "message_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("messages.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("emoji", sa.String(16), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "message_id", "user_id", "emoji", name="uq_message_reaction"
        ),
    )
    op.create_index(
        "ix_message_reactions_message", "message_reactions", ["message_id"]
    )


def downgrade() -> None:
    op.drop_table("message_reactions")
