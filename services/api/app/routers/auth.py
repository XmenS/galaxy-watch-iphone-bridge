from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.schemas.auth import LoginRequest, RefreshRequest, SignupRequest, TokenPair
from app.schemas.user import UserOut
from app.services.auth_service import AuthError, AuthService

router = APIRouter(prefix="/v1/auth", tags=["auth"])


@router.post("/signup", response_model=TokenPair, status_code=201)
async def signup(req: SignupRequest, session: AsyncSession = Depends(get_session)) -> TokenPair:
    try:
        _, pair = await AuthService(session).signup(req)
    except AuthError as e:
        raise HTTPException(status.HTTP_409_CONFLICT, str(e)) from e
    return pair


@router.post("/login", response_model=TokenPair)
async def login(req: LoginRequest, session: AsyncSession = Depends(get_session)) -> TokenPair:
    try:
        _, pair = await AuthService(session).login(req)
    except AuthError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, str(e)) from e
    return pair


@router.post("/refresh", response_model=TokenPair)
async def refresh(req: RefreshRequest, session: AsyncSession = Depends(get_session)) -> TokenPair:
    try:
        return await AuthService(session).refresh_pair(req.refresh_token)
    except AuthError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, str(e)) from e


@router.get("/me", response_model=UserOut)
async def me(
    user=Depends(__import__("app.auth", fromlist=["current_user"]).current_user),
) -> UserOut:
    return UserOut.model_validate(user)
