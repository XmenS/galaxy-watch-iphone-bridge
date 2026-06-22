from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import current_user
from app.database import get_session
from app.models.user import User
from app.schemas.health import IngestRequest, IngestResponse, SamplesPage
from app.services.sync_service import SyncError, SyncService

router = APIRouter(prefix="/v1/sync", tags=["sync"])


@router.post("/ingest", response_model=IngestResponse, status_code=202)
async def ingest(
    body: IngestRequest,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> IngestResponse:
    try:
        return await SyncService(session).ingest(user_id=user.id, device_id=None, req=body)
    except SyncError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e)) from e


@router.get("/samples", response_model=SamplesPage)
async def list_samples(
    cursor: str | None = Query(None, description="ISO timestamp from previous next_cursor"),
    limit: int = Query(500, ge=1, le=2000),
    type: list[str] | None = Query(None, alias="type"),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> SamplesPage:
    try:
        return await SyncService(session).page(
            user_id=user.id, cursor=cursor, limit=limit, types=type
        )
    except SyncError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e)) from e
