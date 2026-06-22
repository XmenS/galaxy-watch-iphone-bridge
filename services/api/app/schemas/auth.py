from datetime import date

from pydantic import BaseModel, EmailStr, Field


class SignupRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=12, max_length=128)
    dob: date | None = None
    install_id: str = Field(min_length=8, max_length=128)
    device_kind: str = Field(pattern="^(android|ios|web)$")
    device_label: str | None = Field(default=None, max_length=128)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)
    install_id: str = Field(min_length=8, max_length=128)
    device_kind: str = Field(pattern="^(android|ios|web)$")
    device_label: str | None = Field(default=None, max_length=128)
    totp_code: str | None = Field(default=None, pattern=r"^\d{6}$")


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"
    access_expires_in: int
    refresh_expires_in: int
