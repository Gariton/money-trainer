from __future__ import annotations

import hmac
from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import Settings
from .database import Database
from .storage import ObjectStorage


bearer_scheme = HTTPBearer(auto_error=False)


def require_api_token(
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Depends(bearer_scheme)
    ],
) -> None:
    settings: Settings = request.app.state.settings
    if (
        credentials is None
        or credentials.scheme.lower() != "bearer"
        or not hmac.compare_digest(credentials.credentials, settings.api_token)
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API token",
            headers={"WWW-Authenticate": "Bearer"},
        )


def get_session(request: Request) -> Iterator[Session]:
    database: Database = request.app.state.database
    yield from database.session()


def get_storage(request: Request) -> ObjectStorage:
    return request.app.state.storage


SessionDependency = Annotated[Session, Depends(get_session)]
StorageDependency = Annotated[ObjectStorage, Depends(get_storage)]

