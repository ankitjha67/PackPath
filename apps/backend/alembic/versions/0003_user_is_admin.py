"""add is_admin to users

Revision ID: 0003_user_is_admin
Revises: 0002_advanced_features
Create Date: 2026-04-12

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0003_user_is_admin"
down_revision = "0002_advanced_features"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "is_admin",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "is_admin")
