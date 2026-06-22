from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import current_admin
from app.database import get_session
from app.models.health import HealthSample
from app.models.sync import SyncJob
from app.models.user import User

router = APIRouter(prefix="/v1/admin", tags=["admin"])


@router.get("/stats")
async def stats(
    _: User = Depends(current_admin),
    session: AsyncSession = Depends(get_session),
) -> dict:
    user_count = (await session.execute(select(func.count(User.id)))).scalar_one()
    sample_count = (await session.execute(select(func.count(HealthSample.id)))).scalar_one()
    job_count = (await session.execute(select(func.count(SyncJob.id)))).scalar_one()
    return {
        "users": int(user_count),
        "samples": int(sample_count),
        "jobs": int(job_count),
    }
