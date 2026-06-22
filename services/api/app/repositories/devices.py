import uuid
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.device import Device, PairCode


class DeviceRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def list_for_user(self, user_id: uuid.UUID) -> list[Device]:
        q = select(Device).where(Device.user_id == user_id).order_by(Device.created_at.desc())
        return list((await self.session.execute(q)).scalars())

    async def upsert(
        self,
        *,
        user_id: uuid.UUID,
        install_id: str,
        kind: str,
        label: str | None = None,
        pub_key: str | None = None,
        app_version: str | None = None,
        os_version: str | None = None,
    ) -> Device:
        stmt = pg_insert(Device).values(
            user_id=user_id,
            install_id=install_id,
            kind=kind,
            label=label,
            pub_key=pub_key,
            app_version=app_version,
            os_version=os_version,
            last_seen_at=datetime.now(timezone.utc),
        ).on_conflict_do_update(
            constraint="uq_device_install",
            set_={
                "label": label,
                "pub_key": pub_key,
                "app_version": app_version,
                "os_version": os_version,
                "last_seen_at": datetime.now(timezone.utc),
            },
        ).returning(Device)
        row = (await self.session.execute(stmt)).scalar_one()
        return row

    async def by_id(self, device_id: uuid.UUID) -> Device | None:
        return await self.session.get(Device, device_id)

    async def revoke(self, device_id: uuid.UUID) -> None:
        d = await self.by_id(device_id)
        if d:
            d.revoked_at = datetime.now(timezone.utc)
            await self.session.flush()


class PairCodeRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def create(self, *, user_id: uuid.UUID, code_hash: str, expires_at: datetime) -> PairCode:
        p = PairCode(user_id=user_id, code_hash=code_hash, expires_at=expires_at)
        self.session.add(p)
        await self.session.flush()
        return p

    async def by_hash(self, code_hash: str) -> PairCode | None:
        q = select(PairCode).where(PairCode.code_hash == code_hash)
        return (await self.session.execute(q)).scalar_one_or_none()
