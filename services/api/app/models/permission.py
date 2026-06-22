import uuid
from enum import Enum

from sqlalchemy import Boolean, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models._mixins import TimestampMixin, UUIDPKMixin


class PermissionScope(str, Enum):
    READ = "read"
    WRITE = "write"


class Permission(Base, UUIDPKMixin, TimestampMixin):
    """Per-metric consent. Tracks user opt-in for each (source -> destination) flow."""

    __tablename__ = "permissions"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "metric_type", "scope", "destination", name="uq_perm_unique"
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    metric_type: Mapped[str] = mapped_column(String(64), nullable=False)  # "heart_rate"
    scope: Mapped[str] = mapped_column(String(16), nullable=False)        # "read" | "write"
    destination: Mapped[str] = mapped_column(String(64), nullable=False)  # "healthkit"
    granted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
