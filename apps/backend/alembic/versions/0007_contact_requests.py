"""contact exchange: per-trip phone-number request/accept

Revision ID: 0007_contact_requests
Revises: 0006_user_bio_country
Create Date: 2026-11-16

A member can request to exchange phone numbers with another member of the
same trip. Numbers are revealed to each other only after the target
accepts, and only within that trip.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "0007_contact_requests"
down_revision = "0006_user_bio_country"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "contact_requests",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            primary_key=True,
        ),
        sa.Column("trip_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("requester_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("status", sa.String(length=10), nullable=False),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("responded_at", sa.TIMESTAMP(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["trip_id"], ["trips.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["requester_id"], ["users.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["target_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "trip_id",
            "requester_id",
            "target_id",
            name="uq_contact_request_direction",
        ),
    )
    op.create_index(
        "ix_contact_requests_trip_id", "contact_requests", ["trip_id"]
    )
    op.create_index(
        "ix_contact_requests_target_id", "contact_requests", ["target_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_contact_requests_target_id", table_name="contact_requests")
    op.drop_index("ix_contact_requests_trip_id", table_name="contact_requests")
    op.drop_table("contact_requests")
