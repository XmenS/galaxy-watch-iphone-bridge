from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.repositories.devices import DeviceRepository
from app.repositories.tokens import RefreshTokenRepository
from app.repositories.users import UserRepository
from app.schemas.auth import LoginRequest, SignupRequest, TokenPair
from app.security.hashing import hash_token
from app.security.jwt import create_access_token, create_refresh_token
from app.security.passwords import hash_password, verify_password
from app.settings import get_settings


class AuthError(Exception):
    pass


class AuthService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.users = UserRepository(session)
        self.devices = DeviceRepository(session)
        self.refresh = RefreshTokenRepository(session)

    async def signup(self, req: SignupRequest) -> tuple[User, TokenPair]:
        if await self.users.by_email(req.email):
            raise AuthError("email already registered")
        user = await self.users.create(
            email=req.email,
            password_hash=hash_password(req.password),
            dob=req.dob,
        )
        device = await self.devices.upsert(
            user_id=user.id,
            install_id=req.install_id,
            kind=req.device_kind,
            label=req.device_label,
        )
        pair = await self._issue_pair(user, device.id)
        return user, pair

    async def login(self, req: LoginRequest) -> tuple[User, TokenPair]:
        user = await self.users.by_email(req.email)
        if not user or not verify_password(req.password, user.password_hash):
            raise AuthError("invalid email or password")
        if not user.is_active:
            raise AuthError("account disabled")
        # TODO: TOTP check using req.totp_code if user.totp_secret
        device = await self.devices.upsert(
            user_id=user.id,
            install_id=req.install_id,
            kind=req.device_kind,
            label=req.device_label,
        )
        pair = await self._issue_pair(user, device.id)
        return user, pair

    async def refresh_pair(self, refresh_token: str) -> TokenPair:
        from app.security.jwt import TokenError, decode_token

        try:
            payload = decode_token(refresh_token, expected_type="refresh")
        except TokenError as e:
            raise AuthError(str(e)) from e

        existing = await self.refresh.get_active(hash_token(refresh_token))
        if existing is None:
            raise AuthError("refresh token revoked or unknown")

        import uuid as _u
        user = await self.users.by_id(_u.UUID(payload["sub"]))
        if user is None or not user.is_active:
            raise AuthError("user not found")

        # rotate
        new_pair = await self._issue_pair(user, existing.device_id)
        await self.refresh.revoke(existing.id)
        return new_pair

    async def _issue_pair(self, user: User, device_id) -> TokenPair:
        s = get_settings()
        access = create_access_token(user_id=user.id, device_id=device_id)
        refresh, expires = create_refresh_token(user_id=user.id, device_id=device_id)
        await self.refresh.create(
            user_id=user.id,
            device_id=device_id,
            token_hash=hash_token(refresh),
            expires_at=expires,
        )
        return TokenPair(
            access_token=access,
            refresh_token=refresh,
            access_expires_in=s.jwt_access_ttl_seconds,
            refresh_expires_in=s.jwt_refresh_ttl_seconds,
        )
