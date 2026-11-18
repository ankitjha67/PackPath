"""gamification: user badges

Revision ID: 0015_user_badges
Revises: 0014_checklist
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0015_user_badges"
down_revision = "0014_checklist"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_badges",
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
        sa.Column("code", sa.String(40), nullable=False),
        sa.Column(
            "earned_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.UniqueConstraint("user_id", "code", name="uq_user_badge"),
    )
    op.create_index("ix_user_badges_user", "user_badges", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_user_badges_user", table_name="user_badges")
    op.drop_table("user_badges")
