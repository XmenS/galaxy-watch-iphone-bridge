import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.repositories.devices import DeviceRepository, PairCodeRepository
from app.repositories.users import UserRepository
from app.schemas.auth import TokenPair
from app.schemas.device import PairCodeOut, RedeemPairCode
from app.security.crypto import generate_pair_code
from app.security.hashing import hash_token
from app.services.auth_service import AuthService
from app.settings import get_settings


class PairingError(Exception):
    pass


class PairingService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.codes = PairCodeRepository(session)
        self.devices = DeviceRepository(session)
        self.users = UserRepository(session)
        self.auth = AuthService(session)

    async def issue(self, user_id: uuid.UUID) -> PairCodeOut:
        s = get_settings()
        code = generate_pair_code()
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=s.pair_code_ttl_seconds)
        await self.codes.create(
            user_id=user_id, code_hash=hash_token(code), expires_at=expires_at
        )
        return PairCodeOut(code=code, expires_at=expires_at)

    async def redeem(self, req: RedeemPairCode) -> tuple[User, TokenPair]:
        record = await self.codes.by_hash(hash_token(req.code))
        if record is None:
            raise PairingError("invalid code")
        if record.consumed_at is not None:
            raise PairingError("code already used")
        if record.expires_at <= datetime.now(timezone.utc):
            raise PairingError("code expired")
        record.consumed_at = datetime.now(timezone.utc)
        await self.session.flush()

        user = await self.users.by_id(record.user_id)
        if user is None:
            raise PairingError("originating account no longer exists")

        device = await self.devices.upsert(
            user_id=user.id,
            install_id=req.install_id,
            kind=req.device_kind,
            label=req.device_label,
            pub_key=req.pub_key,
        )
        pair = await self.auth._issue_pair(user, device.id)  # noqa: SLF001
        return user, pair
