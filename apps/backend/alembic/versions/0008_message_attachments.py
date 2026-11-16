"""chat attachments: image/video/file/location on messages

Revision ID: 0008_message_attachments
Revises: 0007_contact_requests
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0008_message_attachments"
down_revision = "0007_contact_requests"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "messages",
        sa.Column("attachment_kind", sa.String(length=12), nullable=True),
    )
    op.add_column(
        "messages",
        sa.Column("attachment_url", sa.String(length=500), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("messages", "attachment_url")
    op.drop_column("messages", "attachment_kind")
