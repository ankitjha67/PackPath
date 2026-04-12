"""advanced features: safety, expenses, audit, subgroups, subscriptions, events, reminders

Revision ID: 0002_advanced_features
Revises: 0001_initial
Create Date: 2026-04-12

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0002_advanced_features"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- trip_members extensions ---
    op.add_column(
        "trip_members",
        sa.Column(
            "visibility_scope",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{\"type\": \"all\"}'::jsonb"),
        ),
    )
    op.add_column(
        "trip_members",
        sa.Column("share_until", sa.TIMESTAMP(timezone=True), nullable=True),
    )
    op.add_column(
        "trip_members",
        sa.Column(
            "is_ready",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.add_column(
        "trip_members",
        sa.Column("vehicle_label", sa.String(40), nullable=True),
    )
    op.add_column(
        "trip_members",
        sa.Column(
            "subgroup_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
    )
    # Expand the role check constraint to cover the new richer set.
    op.drop_constraint("trip_members_role_check", "trip_members", type_="check")
    op.create_check_constraint(
        "trip_members_role_check",
        "trip_members",
        "role in ('owner','member','driver','navigator','dj','photographer','treasurer')",
    )

    # --- trips extensions ---
    op.add_column(
        "trips", sa.Column("template", sa.String(40), nullable=True)
    )
    op.add_column(
        "trips",
        sa.Column(
            "cover_color",
            sa.String(9),
            nullable=False,
            server_default="#3B82F6",
        ),
    )

    # --- safety_alerts ---
    op.create_table(
        "safety_alerts",
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
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("severity", sa.String(20), nullable=False, server_default="warning"),
        sa.Column(
            "details",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("acknowledged_at", sa.TIMESTAMP(timezone=True)),
        sa.CheckConstraint(
            "kind in ('sos','crash','stranded','speed','fatigue')",
            name="safety_alerts_kind_check",
        ),
        sa.CheckConstraint(
            "severity in ('info','warning','critical')",
            name="safety_alerts_severity_check",
        ),
    )
    op.create_index(
        "ix_safety_alerts_trip_created",
        "safety_alerts",
        ["trip_id", "created_at"],
    )

    # --- audit_logs ---
    op.create_table(
        "audit_logs",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "subject_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "actor_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "trip_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("trips.id", ondelete="CASCADE"),
            nullable=True,
        ),
        sa.Column("action", sa.String(40), nullable=False),
        sa.Column(
            "details",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_audit_logs_subject_created",
        "audit_logs",
        ["subject_user_id", "created_at"],
    )

    # --- subgroups ---
    op.create_table(
        "subgroups",
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
        sa.Column("name", sa.String(60), nullable=False),
        sa.Column("color", sa.String(9), nullable=False, server_default="#10B981"),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_index("ix_subgroups_trip", "subgroups", ["trip_id"])
    op.create_foreign_key(
        "fk_trip_members_subgroup",
        "trip_members",
        "subgroups",
        ["subgroup_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # --- expenses & expense_shares ---
    op.create_table(
        "expenses",
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
            "paid_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("description", sa.String(200), nullable=False),
        sa.Column("amount_cents", sa.BigInteger(), nullable=False),
        sa.Column("currency", sa.String(3), nullable=False, server_default="INR"),
        sa.Column("category", sa.String(20), nullable=False, server_default="other"),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_index("ix_expenses_trip", "expenses", ["trip_id"])
    op.create_table(
        "expense_shares",
        sa.Column(
            "expense_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("expenses.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("share_cents", sa.BigInteger(), nullable=False),
    )

    # --- subscriptions ---
    op.create_table(
        "subscriptions",
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
        sa.Column("provider", sa.String(20), nullable=False),
        sa.Column("plan", sa.String(20), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="trialing"),
        sa.Column("monthly_amount_cents", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("currency", sa.String(3), nullable=False, server_default="INR"),
        sa.Column("paywall_source", sa.String(40), nullable=True),
        sa.Column("started_at", sa.TIMESTAMP(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("renewed_at", sa.TIMESTAMP(timezone=True)),
        sa.Column("cancelled_at", sa.TIMESTAMP(timezone=True)),
        sa.CheckConstraint(
            "provider in ('razorpay','stripe')", name="subscriptions_provider_check"
        ),
        sa.CheckConstraint(
            "plan in ('free','pro','family')", name="subscriptions_plan_check"
        ),
        sa.CheckConstraint(
            "status in ('trialing','active','past_due','cancelled','expired')",
            name="subscriptions_status_check",
        ),
    )
    op.create_index("ix_subscriptions_user", "subscriptions", ["user_id"])

    # --- reminders ---
    op.create_table(
        "reminders",
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
        sa.Column("title", sa.String(120), nullable=False),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("fire_at", sa.TIMESTAMP(timezone=True), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False, server_default="custom"),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("fired_at", sa.TIMESTAMP(timezone=True)),
    )
    op.create_index("ix_reminders_fire_at", "reminders", ["fire_at"])

    # --- events (TimescaleDB hypertable for product telemetry) ---
    op.execute(
        """
        CREATE TABLE events (
            user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
            name       text NOT NULL,
            properties jsonb NOT NULL DEFAULT '{}'::jsonb,
            created_at timestamptz NOT NULL DEFAULT now(),
            session_id text,
            trip_id    uuid REFERENCES trips(id) ON DELETE SET NULL
        );
        """
    )
    op.execute(
        "SELECT create_hypertable('events', 'created_at', "
        "chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);"
    )
    op.execute("CREATE INDEX ix_events_name_time ON events (name, created_at DESC);")
    op.execute(
        "CREATE INDEX ix_events_user_time ON events (user_id, created_at DESC);"
    )

    # --- maps_provider_calls (operational analytics for the routing layer) ---
    op.execute(
        """
        CREATE TABLE maps_provider_calls (
            provider    text NOT NULL,
            endpoint    text NOT NULL,
            duration_ms integer NOT NULL,
            status      smallint NOT NULL,
            created_at  timestamptz NOT NULL DEFAULT now()
        );
        """
    )
    op.execute(
        "SELECT create_hypertable('maps_provider_calls', 'created_at', "
        "chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);"
    )
    op.execute(
        "CREATE INDEX ix_maps_calls_provider_time ON maps_provider_calls (provider, created_at DESC);"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS maps_provider_calls CASCADE")
    op.execute("DROP TABLE IF EXISTS events CASCADE")
    op.drop_index("ix_reminders_fire_at", table_name="reminders")
    op.drop_table("reminders")
    op.drop_index("ix_subscriptions_user", table_name="subscriptions")
    op.drop_table("subscriptions")
    op.drop_table("expense_shares")
    op.drop_index("ix_expenses_trip", table_name="expenses")
    op.drop_table("expenses")
    op.drop_constraint("fk_trip_members_subgroup", "trip_members", type_="foreignkey")
    op.drop_index("ix_subgroups_trip", table_name="subgroups")
    op.drop_table("subgroups")
    op.drop_index("ix_audit_logs_subject_created", table_name="audit_logs")
    op.drop_table("audit_logs")
    op.drop_index(
        "ix_safety_alerts_trip_created", table_name="safety_alerts"
    )
    op.drop_table("safety_alerts")
    op.drop_column("trips", "cover_color")
    op.drop_column("trips", "template")
    op.drop_constraint("trip_members_role_check", "trip_members", type_="check")
    op.create_check_constraint(
        "trip_members_role_check",
        "trip_members",
        "role in ('owner','member')",
    )
    op.drop_column("trip_members", "subgroup_id")
    op.drop_column("trip_members", "vehicle_label")
    op.drop_column("trip_members", "is_ready")
    op.drop_column("trip_members", "share_until")
    op.drop_column("trip_members", "visibility_scope")
