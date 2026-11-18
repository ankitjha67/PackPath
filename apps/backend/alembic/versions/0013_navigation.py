"""navigation: road hazards + detour proposals/votes

Revision ID: 0013_navigation
Revises: 0012_emergency_contacts
Create Date: 2026-11-16
"""
from __future__ import annotations

import geoalchemy2
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0013_navigation"
down_revision = "0012_emergency_contacts"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "road_hazards",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "trip_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("kind", sa.String(20), nullable=False, server_default="other"),
        sa.Column("severity", sa.String(10), nullable=False, server_default="warn"),
        sa.Column(
            "geom",
            geoalchemy2.Geography(geometry_type="POINT", srid=4326),
            nullable=False,
        ),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("expires_at", sa.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("cleared_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column(
            "cleared_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.CheckConstraint(
            "kind in ('pothole','accident','police','traffic','roadblock',"
            "'animal','debris','flood','construction','fuel_closed',"
            "'landslide','other')",
            name="road_hazards_kind_check",
        ),
        sa.CheckConstraint(
            "severity in ('info','warn','danger')",
            name="road_hazards_severity_check",
        ),
    )
    op.create_index("ix_road_hazards_trip", "road_hazards", ["trip_id"])
    op.execute(
        "CREATE INDEX ix_road_hazards_geom ON road_hazards USING gist (geom)"
    )

    op.create_table(
        "detour_proposals",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "trip_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "proposed_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("label", sa.String(160), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column(
            "geom",
            geoalchemy2.Geography(geometry_type="POINT", srid=4326),
            nullable=False,
        ),
        sa.Column(
            "establishment_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("establishments.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("resolved_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column("outcome", sa.String(12), nullable=True),
        sa.CheckConstraint(
            "outcome is null or outcome in ('accepted','rejected','cancelled')",
            name="detour_proposals_outcome_check",
        ),
    )
    op.create_index("ix_detour_proposals_trip", "detour_proposals", ["trip_id"])

    op.create_table(
        "detour_votes",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "proposal_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("detour_proposals.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("choice", sa.String(3), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "choice in ('yes','no')", name="detour_votes_choice_check"
        ),
        sa.UniqueConstraint(
            "proposal_id", "user_id", name="uq_detour_vote_user"
        ),
    )


def downgrade() -> None:
    op.drop_table("detour_votes")
    op.drop_index("ix_detour_proposals_trip", table_name="detour_proposals")
    op.drop_table("detour_proposals")
    op.execute("DROP INDEX IF EXISTS ix_road_hazards_geom")
    op.drop_index("ix_road_hazards_trip", table_name="road_hazards")
    op.drop_table("road_hazards")
