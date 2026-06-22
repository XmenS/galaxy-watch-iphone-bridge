import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator


CANONICAL_TYPES = {
    "steps", "distance", "active_energy", "basal_energy", "heart_rate",
    "resting_heart_rate", "hrv", "spo2", "respiratory_rate", "body_temperature",
    "blood_pressure_systolic", "blood_pressure_diastolic",
    "body_mass", "body_fat_percentage", "lean_body_mass",
    "sleep_in_bed", "sleep_awake", "sleep_light", "sleep_deep", "sleep_rem",
    "workout", "mindful_minutes", "stand_hours", "vo2_max", "stress_score",
}


class HealthSampleIn(BaseModel):
    """Inbound sample from a mobile client. Either plaintext or E2E envelope."""

    client_uid: str = Field(min_length=8, max_length=64)
    source: str = Field(min_length=2, max_length=64)
    type: str
    started_at: datetime
    ended_at: datetime
    unit: str | None = Field(default=None, max_length=32)
    value: float | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)
    # E2E envelope (mutually exclusive with value+unit when E2E required)
    nonce_b64: str | None = None
    ciphertext_b64: str | None = None

    @model_validator(mode="after")
    def _validate(self) -> "HealthSampleIn":
        if self.type not in CANONICAL_TYPES:
            raise ValueError(f"unknown canonical type: {self.type}")
        if self.ended_at < self.started_at:
            raise ValueError("ended_at must be >= started_at")
        encrypted = self.nonce_b64 is not None and self.ciphertext_b64 is not None
        plaintext = self.value is not None
        if not encrypted and not plaintext:
            raise ValueError("sample must include either value or ciphertext envelope")
        return self


class HealthSampleOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    client_uid: str
    source: str
    type: str
    started_at: datetime
    ended_at: datetime
    unit: str | None
    value: float | None
    metadata_json: dict[str, Any] = Field(default_factory=dict, alias="metadata")
    nonce_b64: str | None = None
    ciphertext_b64: str | None = None


class IngestRequest(BaseModel):
    source: str = Field(min_length=2, max_length=64)
    samples: list[HealthSampleIn] = Field(min_length=1, max_length=5000)


class IngestResponse(BaseModel):
    job_id: uuid.UUID
    accepted: int
    duplicates: int
    rejected: int


class SamplesPage(BaseModel):
    items: list[HealthSampleOut]
    next_cursor: str | None
