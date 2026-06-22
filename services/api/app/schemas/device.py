import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class DeviceCreate(BaseModel):
    install_id: str = Field(min_length=8, max_length=128)
    kind: str = Field(pattern="^(android|ios|web)$")
    label: str | None = Field(default=None, max_length=128)
    pub_key: str | None = Field(default=None, max_length=256)
    app_version: str | None = Field(default=None, max_length=32)
    os_version: str | None = Field(default=None, max_length=32)


class DeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    kind: str
    label: str | None
    pub_key: str | None
    app_version: str | None
    os_version: str | None
    last_seen_at: datetime | None
    revoked_at: datetime | None
    created_at: datetime


class PairCodeOut(BaseModel):
    code: str
    expires_at: datetime


class RedeemPairCode(BaseModel):
    code: str = Field(min_length=8, max_length=20)
    install_id: str = Field(min_length=8, max_length=128)
    device_kind: str = Field(pattern="^(android|ios|web)$")
    device_label: str | None = Field(default=None, max_length=128)
    pub_key: str | None = Field(default=None, max_length=256)
