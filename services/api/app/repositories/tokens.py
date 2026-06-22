import uuid
from datetime import datetime, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.token import RefreshToken


class RefreshTokenRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(
        self,
        *,
        user_id: uuid.UUID,
        device_id: uuid.UUID | None,
        token_hash: str,
        expires_at: datetime,
    ) -> RefreshToken:
        rt = RefreshToken(
            user_id=user_id,
            device_id=device_id,
            token_hash=token_hash,
            expires_at=expires_at,
        )
        self.session.add(rt)
        await self.session.flush()
        return rt

    async def get_active(self, token_hash: str) -> RefreshToken | None:
        q = select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.expires_at > datetime.now(timezone.utc),
        )
        return (await self.session.execute(q)).scalar_one_or_none()

    async def revoke(self, token_id: uuid.UUID, replaced_by_id: uuid.UUID | None = None) -> None:
        q = (
            update(RefreshToken)
            .where(RefreshToken.id == token_id)
            .values(revoked_at=datetime.now(timezone.utc), replaced_by_id=replaced_by_id)
        )
        await self.session.execute(q)
