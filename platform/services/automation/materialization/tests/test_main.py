import os
from collections.abc import Generator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from main import _render_repo, main


@pytest.fixture
def mock_feast_feature_store() -> Generator[MagicMock]:
    with patch("main.FeatureStore") as mock:
        yield mock


def test_main_materialization(mock_feast_feature_store: MagicMock) -> None:
    # Setup
    mock_store_instance = MagicMock()
    mock_feast_feature_store.return_value = mock_store_instance

    # Mock datetime to have a fixed "now"
    fixed_now = datetime(2024, 1, 2, 12, 0, 0, tzinfo=UTC)

    with (
        patch("main.datetime") as mock_datetime,
        patch("main.subprocess.run") as mock_subprocess,
    ):
        mock_datetime.now.return_value = fixed_now
        mock_datetime.side_effect = lambda *a, **kw: datetime(*a, **kw)
        mock_subprocess.return_value = MagicMock(returncode=0, stdout="Applied", stderr="")

        # Execute
        main()

        # Verify subprocess.run was called for feast apply
        mock_subprocess.assert_called_once()

        # Verify FeatureStore was initialized with correct path
        mock_feast_feature_store.assert_called_once_with(repo_path="/app/feature_repo")

        # Verify materialize was called
        mock_store_instance.materialize.assert_called_once()

        # Check args
        _args, kwargs = mock_store_instance.materialize.call_args
        start_date = kwargs.get("start_date")
        end_date = kwargs.get("end_date")

        assert end_date == fixed_now
        assert start_date == fixed_now - timedelta(hours=24)


def test_main_custom_repo_path(mock_feast_feature_store: MagicMock) -> None:
    # Setup
    custom_path = "/custom/repo/path"
    with (
        patch.dict(os.environ, {"FEAST_REPO_PATH": custom_path}),
        patch("main.datetime") as mock_datetime,
        patch("main.subprocess.run") as mock_subprocess,
    ):
        mock_datetime.now.return_value = datetime(2024, 1, 1, tzinfo=UTC)
        mock_subprocess.return_value = MagicMock(returncode=0, stdout="Applied", stderr="")

        # Execute
        main()

        # Verify
        mock_feast_feature_store.assert_called_once_with(repo_path=custom_path)


def test_render_repo_substitutes_and_copies(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    template_dir = tmp_path / "template"
    template_dir.mkdir()
    (template_dir / "feature_store.yaml.tmpl").write_text(
        "project: demo\nuser: ${CLICKHOUSE_USER}\npassword: ${CLICKHOUSE_PASSWORD}\n"
    )
    (template_dir / "definitions.py").write_text("# feature defs\n")
    repo_dir = tmp_path / "repo"

    monkeypatch.setenv("FEAST_TEMPLATE_DIR", str(template_dir))
    monkeypatch.setenv("CLICKHOUSE_USER", "ch_user")
    # Password with /, +, =, and a literal \1 - a function replacement must NOT
    # treat \1 as a regex backreference (the whole reason _sub is a callable).
    monkeypatch.setenv("CLICKHOUSE_PASSWORD", "s3cr3t/+=\\1")

    _render_repo(str(repo_dir))

    rendered = (repo_dir / "feature_store.yaml").read_text()
    assert "user: ch_user" in rendered
    assert "password: s3cr3t/+=\\1" in rendered
    assert "${" not in rendered
    assert (repo_dir / "definitions.py").read_text() == "# feature defs\n"


def test_render_repo_noop_without_template_dir(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("FEAST_TEMPLATE_DIR", raising=False)
    repo_dir = tmp_path / "repo"

    _render_repo(str(repo_dir))

    assert not repo_dir.exists()


def test_render_repo_raises_on_missing_var(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    template_dir = tmp_path / "template"
    template_dir.mkdir()
    (template_dir / "feature_store.yaml.tmpl").write_text("password: ${MISSING_VAR}\n")
    (template_dir / "definitions.py").write_text("# defs\n")
    repo_dir = tmp_path / "repo"

    monkeypatch.setenv("FEAST_TEMPLATE_DIR", str(template_dir))
    monkeypatch.delenv("MISSING_VAR", raising=False)

    with pytest.raises(KeyError, match="MISSING_VAR"):
        _render_repo(str(repo_dir))


def test_main_raises_on_apply_failure(mock_feast_feature_store: MagicMock) -> None:
    with (
        patch("main.datetime") as mock_datetime,
        patch("main.subprocess.run") as mock_subprocess,
    ):
        mock_datetime.now.return_value = datetime(2024, 1, 1, tzinfo=UTC)
        mock_subprocess.return_value = MagicMock(
            returncode=1, stdout="", stderr="boom: connection refused"
        )

        with pytest.raises(RuntimeError, match="feast apply failed"):
            main()

    # materialize must NOT run when apply failed - a stale/empty registry
    # would otherwise silently materialize nothing.
    mock_feast_feature_store.return_value.materialize.assert_not_called()
