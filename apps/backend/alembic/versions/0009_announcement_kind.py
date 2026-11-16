"""allow 'announcement' as a message kind (marshall broadcasts)

Revision ID: 0009_announcement_kind
Revises: 0008_message_attachments
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op

revision = "0009_announcement_kind"
down_revision = "0008_message_attachments"
branch_labels = None
depends_on = None

_OLD = "kind in ('text','system','arrival','leave','join')"
_NEW = "kind in ('text','system','arrival','leave','join','announcement')"


def upgrade() -> None:
    op.drop_constraint("messages_kind_check", "messages", type_="check")
    op.create_check_constraint("messages_kind_check", "messages", _NEW)


def downgrade() -> None:
    op.drop_constraint("messages_kind_check", "messages", type_="check")
    op.create_check_constraint("messages_kind_check", "messages", _OLD)
