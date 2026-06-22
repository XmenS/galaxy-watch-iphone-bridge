import uuid
from datetime import datetime

from sqlalchemy import (
    JSON,
    DateTime,
    Float,
    ForeignKey,
    Index,
    LargeBinary,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models._mixins import TimestampMixin, UUIDPKMixin


class HealthRecord(Base, UUIDPKMixin, TimestampMixin):
    """A logical record / session (e.g. one workout, one sleep window).

    A record may contain many samples (HR points within a workout).
    """

    __tablename__ = "health_records"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    source: Mapped[str] = mapped_column(String(64), nullable=False)
    kind: Mapped[str] = mapped_column(String(64), nullable=False)            # e.g. "workout","sleep"
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    metadata_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)


class HealthSample(Base, UUIDPKMixin, TimestampMixin):
    """One discrete measurement.

    Idempotency is per (user_id, source, client_uid) — clients pick a stable UUIDv7
    so retries dedupe naturally.
    """

    __tablename__ = "health_samples"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "source", "client_uid", name="uq_sample_user_source_clientuid"
        ),
        Index("ix_sample_user_type_started", "user_id", "type", "started_at"),
        Index("ix_sample_user_started", "user_id", "started_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    record_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("health_records.id", ondelete="SET NULL"),
        nullable=True,
    )
    source: Mapped[str] = mapped_column(String(64), nullable=False)        # "samsung-health"
    client_uid: Mapped[str] = mapped_column(String(64), nullable=False)    # UUIDv7
    type: Mapped[str] = mapped_column(String(64), nullable=False)          # canonical type
    unit: Mapped[str | None] = mapped_column(String(32), nullable=True)
    value: Mapped[float | None] = mapped_column(Float, nullable=True)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    metadata_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)

    # E2E envelope (when enabled): server only stores ciphertext + nonce.
    nonce: Mapped[bytes | None] = mapped_column(LargeBinary(24), nullable=True)
    ciphertext: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    blob_url: Mapped[str | None] = mapped_column(String(512), nullable=True)  # if offloaded to S3
