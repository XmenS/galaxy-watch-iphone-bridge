import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def by_id(self, user_id: uuid.UUID) -> User | None:
        return await self.session.get(User, user_id)

    async def by_email(self, email: str) -> User | None:
        q = select(User).where(User.email == email.lower())
        return (await self.session.execute(q)).scalar_one_or_none()

    async def create(self, *, email: str, password_hash: str, dob=None) -> User:
        user = User(email=email.lower(), password_hash=password_hash, dob=dob)
        self.session.add(user)
        await self.session.flush()
        return user
