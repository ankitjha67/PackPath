"""marshall ops: pace/gap, mute, vehicle, co-marshall & sweep roles

Revision ID: 0019_marshall_ops
Revises: 0018_marshall_controls
Create Date: 2026-11-18
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0019_marshall_ops"
down_revision = "0018_marshall_controls"
branch_labels = None
depends_on = None

_OLD_ROLES = "('owner','member','driver','navigator','dj','photographer','treasurer')"
_NEW_ROLES = (
    "('owner','comarshall','member','driver','navigator','sweep',"
    "'dj','photographer','treasurer')"
)


def upgrade() -> None:
    op.add_column("trips", sa.Column("target_pace_kmh", sa.Integer(), nullable=True))
    op.add_column("trips", sa.Column("max_gap_km", sa.Float(), nullable=True))
    op.add_column(
        "trip_members",
        sa.Column(
            "muted", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
    )
    op.drop_constraint("trip_members_role_check", "trip_members", type_="check")
    op.create_check_constraint(
        "trip_members_role_check", "trip_members", f"role in {_NEW_ROLES}"
    )


def downgrade() -> None:
    op.drop_constraint("trip_members_role_check", "trip_members", type_="check")
    op.create_check_constraint(
        "trip_members_role_check", "trip_members", f"role in {_OLD_ROLES}"
    )
    op.drop_column("trip_members", "muted")
    op.drop_column("trips", "max_gap_km")
    op.drop_column("trips", "target_pace_kmh")
