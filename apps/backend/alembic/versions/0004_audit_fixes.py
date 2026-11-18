"""audit fixes: widen trip_members.role, add 'pending' subscription status

Revision ID: 0004_audit_fixes
Revises: 0003_user_is_admin
Create Date: 2026-08-10

Fixes two model/DB drifts surfaced by the audit:

* ``trip_members.role`` was created as ``varchar(10)`` but the role CHECK
  constraint (widened in 0002) allows values up to 12 chars (e.g.
  "photographer"), so assigning those roles failed at the DB.
* Client-created subscription stubs are now written as ``pending`` (unpaid)
  until a verified provider webhook activates them, so they need to be a
  legal status value and must stay excluded from revenue reporting.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "0004_audit_fixes"
down_revision = "0003_user_is_admin"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "trip_members",
        "role",
        type_=sa.String(20),
        existing_type=sa.String(10),
        existing_nullable=False,
    )
    op.drop_constraint(
        "subscriptions_status_check", "subscriptions", type_="check"
    )
    op.create_check_constraint(
        "subscriptions_status_check",
        "subscriptions",
        "status in ('pending','trialing','active','past_due','cancelled','expired')",
    )


def downgrade() -> None:
    op.drop_constraint(
        "subscriptions_status_check", "subscriptions", type_="check"
    )
    op.create_check_constraint(
        "subscriptions_status_check",
        "subscriptions",
        "status in ('trialing','active','past_due','cancelled','expired')",
    )
    op.alter_column(
        "trip_members",
        "role",
        type_=sa.String(10),
        existing_type=sa.String(20),
        existing_nullable=False,
    )
