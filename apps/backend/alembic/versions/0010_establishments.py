"""establishments (places) + ratings — markable, ratable, reusable across trips

Revision ID: 0010_establishments
Revises: 0009_announcement_kind
Create Date: 2026-11-16
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0010_establishments"
down_revision = "0009_announcement_kind"
branch_labels = None
depends_on = None

_CATS = (
    "'fuel','food','repair','lodging','viewpoint','medical','atm',"
    "'parking','water','shop','other'"
)


def upgrade() -> None:
    op.create_table(
        "establishments",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column(
            "category", sa.String(20), nullable=False, server_default="other"
        ),
        sa.Column("address", sa.String(300), nullable=True),
        sa.Column("phone", sa.String(30), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column(
            "created_by",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            f"category in ({_CATS})", name="establishments_category_check"
        ),
    )
    op.execute(
        "ALTER TABLE establishments ADD COLUMN geom geography(Point, 4326) NOT NULL"
    )
    op.execute(
        "CREATE INDEX ix_establishments_geom ON establishments USING GIST (geom)"
    )
    op.create_index(
        "ix_establishments_category", "establishments", ["category"]
    )

    op.create_table(
        "establishment_ratings",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "establishment_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("establishments.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("stars", sa.SmallInteger(), nullable=False),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("tags", sa.String(200), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.TIMESTAMP(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "stars between 1 and 5", name="establishment_ratings_stars_check"
        ),
        sa.UniqueConstraint(
            "establishment_id", "user_id", name="uq_establishment_rating_user"
        ),
    )
    op.create_index(
        "ix_establishment_ratings_place",
        "establishment_ratings",
        ["establishment_id"],
    )


def downgrade() -> None:
    op.drop_table("establishment_ratings")
    op.drop_index("ix_establishments_geom", table_name="establishments")
    op.drop_table("establishments")
