"""initial schema: users, trips, members, waypoints, messages, devices, locations hypertable

Revision ID: 0001_initial
Revises:
Create Date: 2026-04-12

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Extensions — idempotent in case they were not pre-installed.
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    op.execute("CREATE EXTENSION IF NOT EXISTS timescaledb")

    op.create_table(
        "users",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("phone", sa.String(20), nullable=False, unique=True),
        sa.Column("display_name", sa.String(80)),
        sa.Column("avatar_url", sa.String(500)),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )

    op.create_table(
        "trips",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="planned"),
        sa.Column("start_at", sa.TIMESTAMP(timezone=True)),
        sa.Column("end_at", sa.TIMESTAMP(timezone=True)),
        sa.Column("join_code", sa.String(6), nullable=False, unique=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "status in ('planned','active','ended','cancelled')",
            name="trips_status_check",
        ),
    )
    op.create_index("ix_trips_owner_id", "trips", ["owner_id"])

    op.create_table(
        "trip_members",
        sa.Column(
            "trip_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("role", sa.String(10), nullable=False, server_default="member"),
        sa.Column("color", sa.String(9), nullable=False, server_default="#3B82F6"),
        sa.Column(
            "joined_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("left_at", sa.TIMESTAMP(timezone=True)),
        sa.Column(
            "ghost_mode", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
        sa.CheckConstraint(
            "role in ('owner','member')", name="trip_members_role_check"
        ),
    )
    op.create_index("ix_trip_members_user_id", "trip_members", ["user_id"])

    op.create_table(
        "waypoints",
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
        sa.Column("position", sa.Integer, nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column(
            "arrival_radius_m", sa.Integer, nullable=False, server_default="150"
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.execute(
        "ALTER TABLE waypoints ADD COLUMN geom geography(Point, 4326) NOT NULL"
    )
    op.execute("CREATE INDEX ix_waypoints_geom ON waypoints USING GIST (geom)")
    op.create_index("ix_waypoints_trip_id", "waypoints", ["trip_id", "position"])

    op.create_table(
        "messages",
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
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("body", sa.Text, nullable=False),
        sa.Column("kind", sa.String(20), nullable=False, server_default="text"),
        sa.Column(
            "sent_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "kind in ('text','system','arrival','leave','join')",
            name="messages_kind_check",
        ),
    )
    op.create_index("ix_messages_trip_sent", "messages", ["trip_id", "sent_at"])

    op.create_table(
        "devices",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("fcm_token", sa.String(500), nullable=False, unique=True),
        sa.Column("platform", sa.String(10), nullable=False),
        sa.Column(
            "last_seen_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )

    # locations is a TimescaleDB hypertable. Composite PK includes time so the
    # hypertable can partition on recorded_at.
    op.execute(
        """
        CREATE TABLE locations (
            user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            trip_id     uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
            geom        geography(Point, 4326) NOT NULL,
            heading     real,
            speed_mps   real,
            battery_pct smallint,
            recorded_at timestamptz NOT NULL,
            PRIMARY KEY (user_id, trip_id, recorded_at)
        );
        """
    )
    op.execute(
        "SELECT create_hypertable('locations', 'recorded_at', "
        "chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);"
    )
    op.execute(
        "CREATE INDEX ix_locations_trip_time ON locations (trip_id, recorded_at DESC);"
    )
    op.execute("CREATE INDEX ix_locations_geom ON locations USING GIST (geom);")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS locations CASCADE")
    op.drop_table("devices")
    op.drop_index("ix_messages_trip_sent", table_name="messages")
    op.drop_table("messages")
    op.drop_index("ix_waypoints_trip_id", table_name="waypoints")
    op.execute("DROP INDEX IF EXISTS ix_waypoints_geom")
    op.drop_table("waypoints")
    op.drop_index("ix_trip_members_user_id", table_name="trip_members")
    op.drop_table("trip_members")
    op.drop_index("ix_trips_owner_id", table_name="trips")
    op.drop_table("trips")
    op.drop_table("users")
