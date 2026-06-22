"""Sync SQLAlchemy session for Celery tasks — Celery doesn't play nicely with async."""
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.settings import settings

_sync_url = str(settings.database_url).replace("+asyncpg", "")
engine = create_engine(_sync_url, pool_pre_ping=True)
SessionLocal = sessionmaker(engine, expire_on_commit=False, class_=Session)
