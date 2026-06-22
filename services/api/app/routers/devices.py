import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import current_user
from app.database import get_session
from app.models.user import User
from app.repositories.devices import DeviceRepository
from app.schemas.auth import TokenPair
from app.schemas.device import DeviceCreate, DeviceOut, PairCodeOut, RedeemPairCode
from app.services.pairing_service import PairingError, PairingService

router = APIRouter(prefix="/v1/devices", tags=["devices"])


@router.get("", response_model=list[DeviceOut])
async def list_devices(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> list[DeviceOut]:
    rows = await DeviceRepository(session).list_for_user(user.id)
    return [DeviceOut.model_validate(r) for r in rows]


@router.post("", response_model=DeviceOut, status_code=201)
async def register_device(
    body: DeviceCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> DeviceOut:
    d = await DeviceRepository(session).upsert(
        user_id=user.id,
        install_id=body.install_id,
        kind=body.kind,
        label=body.label,
        pub_key=body.pub_key,
        app_version=body.app_version,
        os_version=body.os_version,
    )
    return DeviceOut.model_validate(d)


@router.delete("/{device_id}", status_code=204)
async def revoke_device(
    device_id: uuid.UUID,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    repo = DeviceRepository(session)
    d = await repo.by_id(device_id)
    if not d or d.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    await repo.revoke(device_id)


@router.post("/pair-code", response_model=PairCodeOut)
async def issue_pair_code(
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> PairCodeOut:
    return await PairingService(session).issue(user.id)


@router.post("/redeem", response_model=TokenPair)
async def redeem_pair_code(
    body: RedeemPairCode,
    session: AsyncSession = Depends(get_session),
) -> TokenPair:
    try:
        _, pair = await PairingService(session).redeem(body)
    except PairingError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, str(e)) from e
    return pair
