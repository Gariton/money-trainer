from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool


class Base(DeclarativeBase):
    pass


class Database:
    def __init__(self, url: str) -> None:
        engine_kwargs: dict[str, object] = {"pool_pre_ping": True}
        if url.startswith("sqlite"):
            engine_kwargs["connect_args"] = {"check_same_thread": False}
            if ":memory:" in url:
                engine_kwargs["poolclass"] = StaticPool
        self.engine = create_engine(url, **engine_kwargs)
        self.session_factory = sessionmaker(
            bind=self.engine,
            class_=Session,
            expire_on_commit=False,
            autoflush=False,
        )

    def create_schema(self) -> None:
        # Import registers all mappings on Base.metadata.
        from . import db_models  # noqa: F401

        Base.metadata.create_all(self.engine)

    def session(self) -> Iterator[Session]:
        db = self.session_factory()
        try:
            yield db
        finally:
            db.close()

    def dispose(self) -> None:
        self.engine.dispose()

