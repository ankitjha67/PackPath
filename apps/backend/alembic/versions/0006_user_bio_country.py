"""add bio + country to users

Revision ID: 0006_user_bio_country
Revises: 0005_backfill_user_identity
Create Date: 2026-11-16

Richer, permanent profiles: a short bio and a free-text country/region.
Both are nullable and public-profile fields (never the phone number).
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0006_user_bio_country"
down_revision = "0005_backfill_user_identity"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("bio", sa.String(length=300), nullable=True))
    op.add_column(
        "users", sa.Column("country", sa.String(length=60), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("users", "country")
    op.drop_column("users", "bio")
