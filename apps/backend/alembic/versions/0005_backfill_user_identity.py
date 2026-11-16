"""backfill display_name + avatar_url for users that predate identity minting

Revision ID: 0005_backfill_user_identity
Revises: 0004_audit_fixes
Create Date: 2026-11-16

Users created before sign-up started minting a Reddit-style handle have a
null ``display_name``/``avatar_url``, so every surface rendered their raw
UUID. Give each one a generated identity. New users get theirs at sign-up.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

from app.services.identity import new_identity


revision = "0005_backfill_user_identity"
down_revision = "0004_audit_fixes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    rows = bind.execute(
        sa.text("SELECT id FROM users WHERE display_name IS NULL")
    ).fetchall()
    for (user_id,) in rows:
        display_name, avatar_url = new_identity()
        bind.execute(
            sa.text(
                "UPDATE users SET display_name = :n, avatar_url = :a "
                "WHERE id = :id"
            ),
            {"n": display_name, "a": avatar_url, "id": user_id},
        )


def downgrade() -> None:
    # Identities are cosmetic; nothing to reverse. (Leaving them in place is
    # harmless and avoids wiping names a user may already recognize.)
    pass
