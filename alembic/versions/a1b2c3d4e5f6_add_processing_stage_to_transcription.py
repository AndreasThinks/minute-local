"""add processing_stage to transcription

Revision ID: a1b2c3d4e5f6
Revises: 9d080ca9fe6c
Create Date: 2026-01-14

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, None] = "9d080ca9fe6c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add the processing_stage column with default value
    op.add_column(
        "transcription",
        sa.Column(
            "processing_stage",
            sa.String(),
            nullable=False,
            server_default="queued",
        ),
    )


def downgrade() -> None:
    op.drop_column("transcription", "processing_stage")
