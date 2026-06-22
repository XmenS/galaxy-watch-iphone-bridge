import uuid
from datetime import datetime
from enum import Enum

from sqlalchemy import Boolean, DateTime, ForeignKey, LargeBinary, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models._mixins import TimestampMixin, UUIDPKMixin


class IntegrationKind(str, Enum):
    SAMSUNG_HEALTH = "samsung-health"
    HEALTH_CONNECT = "health-connect"
    APPLE_HEALTH = "apple-health"
    FITBIT = "fitbit"
    GARMIN = "garmin"
    WEBHOOK = "webhook"


class Integration(Base, UUIDPKMixin, TimestampMixin):
    __tablename__ = "integrations"
    __table_args__ = (
        UniqueConstraint("user_id", "kind", name="uq_user_integration_kind"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    kind: Mapped[str] = mapped_column(String(64), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    config: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    # encrypted blob holding refresh tokens / credentials
    secret_ciphertext: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    secret_nonce: Mapped[bytes | None] = mapped_column(LargeBinary(24), nullable=True)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_cursor: Mapped[str | None] = mapped_column(String(128))
