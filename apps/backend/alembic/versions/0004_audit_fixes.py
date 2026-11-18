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
    # Guard against data loss: this downgrade narrows trip_members.role back to
    # varchar(10) and drops 'pending' from the subscription statuses. If rows
    # already use the wider values, silently applying it would truncate roles
    # or violate the re-added CHECK — so refuse with a clear message instead.
    bind = op.get_bind()
    long_roles = bind.execute(
        sa.text("SELECT count(*) FROM trip_members WHERE length(role) > 10")
    ).scalar()
    if long_roles:
        raise RuntimeError(
            f"cannot downgrade: {long_roles} trip_members row(s) have a role "
            "longer than 10 chars (e.g. 'photographer'); reassign them first"
        )
    pending = bind.execute(
        sa.text("SELECT count(*) FROM subscriptions WHERE status = 'pending'")
    ).scalar()
    if pending:
        raise RuntimeError(
            f"cannot downgrade: {pending} subscription(s) have status "
            "'pending'; resolve them before downgrading"
        )

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
