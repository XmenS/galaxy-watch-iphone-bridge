from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import ORJSONResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from starlette.requests import Request
from starlette.responses import Response

from app import __version__
from app.core.logging import configure_logging, logger
from app.core.redis import close_redis
from app.database import dispose_engine, init_engine
from app.routers import admin, auth, devices, health_check, sync
from app.settings import get_settings


limiter = Limiter(key_func=get_remote_address)


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_logging()
    init_engine()
    logger().info("api.startup", version=__version__, env=get_settings().env)
    try:
        yield
    finally:
        await close_redis()
        await dispose_engine()
        logger().info("api.shutdown")


def make_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(
        title="Galaxy Health Bridge",
        version=__version__,
        default_response_class=ORJSONResponse,
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
    )

    app.state.limiter = limiter

    @app.exception_handler(RateLimitExceeded)
    async def _ratelimit(request: Request, exc: RateLimitExceeded) -> Response:
        return ORJSONResponse(
            {"detail": "rate limit exceeded"}, status_code=429
        )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=s.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health_check.router)
    app.include_router(auth.router)
    app.include_router(devices.router)
    app.include_router(sync.router)
    app.include_router(admin.router)

    if s.prometheus_enabled:
        @app.get("/metrics", include_in_schema=False)
        def metrics() -> Response:
            return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    return app


app = make_app()
