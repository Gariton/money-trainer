from __future__ import annotations

import pytest

from app.services import assign_capture_session_split
from app.storage import LocalObjectStorage, UnsafeStorageKey, validate_storage_key


def test_capture_session_split_is_deterministic_and_in_range(settings) -> None:
    sessions = [f"capture-{index}" for index in range(1000)]
    first = {
        session: assign_capture_session_split(session, settings).value
        for session in sessions
    }
    second = {
        session: assign_capture_session_split(session, settings).value
        for session in reversed(sessions)
    }
    assert first == second
    counts = {split: list(first.values()).count(split) for split in ("train", "validation", "test")}
    assert 600 < counts["train"] < 800
    assert 80 < counts["validation"] < 220
    assert 80 < counts["test"] < 220


@pytest.mark.parametrize(
    "key", ["../secret", "/absolute/path", "images/../../secret", "bad\\path"]
)
def test_storage_rejects_path_traversal(settings, key: str) -> None:
    storage = LocalObjectStorage(settings.data_root)
    with pytest.raises(UnsafeStorageKey):
        validate_storage_key(key)
    with pytest.raises(UnsafeStorageKey):
        storage.local_path(key)

