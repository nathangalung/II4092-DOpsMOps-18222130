import sys
from collections.abc import Generator
from itertools import count
from unittest.mock import MagicMock, patch

import pytest
from kubernetes.config.config_exception import ConfigException

from main import main


@pytest.fixture
def mock_k8s_config() -> Generator[MagicMock]:
    with patch("main.config") as mock:
        mock.ConfigException = ConfigException
        yield mock


@pytest.fixture
def mock_k8s_client() -> Generator[MagicMock]:
    with patch("main.client") as mock:
        yield mock


@pytest.fixture
def mock_time() -> Generator[MagicMock]:
    with patch("main.time") as mock:
        # Simulate monotonically advancing time (1s per call)
        base = 1700000000
        counter = count()
        mock.time.side_effect = lambda: base + next(counter)
        mock.sleep = MagicMock()
        yield mock


@pytest.fixture(autouse=True)
def _mock_argv() -> Generator[None]:
    with patch.object(sys, "argv", ["main.py", "--check-and-retrain"]):
        yield


@pytest.fixture
def mock_valkey_with_drift() -> Generator[MagicMock]:
    """Mock Valkey (redis-py over RESP) that returns a drift event exceeding the PSI threshold."""
    with patch("main.redis.Redis") as mock:
        mock_instance = MagicMock()
        mock.return_value = mock_instance
        mock_pubsub = MagicMock()
        mock_instance.pubsub.return_value = mock_pubsub
        # Return one drift event, then None (end of messages)
        mock_pubsub.get_message.side_effect = [
            {"type": "subscribe", "data": None},
            {
                "type": "message",
                "data": b"hourly:value:0.5",  # scale:feature:psi exceeding threshold
            },
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        ]
        # No existing retrain jobs (cooldown check)
        mock_instance.keys.return_value = []
        yield mock


@pytest.fixture
def mock_valkey_no_drift() -> Generator[MagicMock]:
    """Mock Valkey (redis-py over RESP) with no drift events."""
    with patch("main.redis.Redis") as mock:
        mock_instance = MagicMock()
        mock.return_value = mock_instance
        mock_pubsub = MagicMock()
        mock_instance.pubsub.return_value = mock_pubsub
        mock_pubsub.get_message.return_value = None
        yield mock


def test_main_incluster_config(
    mock_k8s_config: MagicMock,
    mock_k8s_client: MagicMock,
    mock_time: MagicMock,
    mock_valkey_with_drift: MagicMock,
) -> None:
    # Setup
    batch_v1_instance = MagicMock()
    mock_k8s_client.BatchV1Api.return_value = batch_v1_instance

    # Execute
    main()

    # Verify config loading
    mock_k8s_config.load_incluster_config.assert_called_once()
    mock_k8s_config.load_kube_config.assert_not_called()

    # Verify Job creation
    assert batch_v1_instance.create_namespaced_job.called
    call_args = batch_v1_instance.create_namespaced_job.call_args
    assert call_args is not None

    assert call_args[1]["namespace"] == "model-lifecycle"

    # Verify container spec via V1Container constructor args
    container_call_args = mock_k8s_client.V1Container.call_args
    assert container_call_args[1]["name"] == "trainer"

    # Verify env vars via V1EnvVar constructor calls
    env_calls = mock_k8s_client.V1EnvVar.call_args_list
    env_vars = {call[1]["name"]: call[1]["value"] for call in env_calls}
    assert env_vars["MODE"] == "retrain"


def test_main_kube_config_fallback(
    mock_k8s_config: MagicMock,
    mock_k8s_client: MagicMock,
    mock_time: MagicMock,
    mock_valkey_no_drift: MagicMock,
) -> None:
    # Setup - incluster config fails, falls back to kube config
    mock_k8s_config.load_incluster_config.side_effect = ConfigException("Error")

    batch_v1_instance = MagicMock()
    mock_k8s_client.BatchV1Api.return_value = batch_v1_instance

    # Execute
    main()

    # Verify fallback
    mock_k8s_config.load_incluster_config.assert_called_once()
    mock_k8s_config.load_kube_config.assert_called_once()


def test_main_custom_env_vars(
    mock_k8s_config: MagicMock,
    mock_k8s_client: MagicMock,
    mock_time: MagicMock,
    mock_valkey_with_drift: MagicMock,
) -> None:
    # Setup — patch Config class attributes directly since they're
    # evaluated at import time (os.getenv in class body)
    batch_v1_instance = MagicMock()
    mock_k8s_client.BatchV1Api.return_value = batch_v1_instance

    with (
        patch("main.Config.NAMESPACE", "custom-ns"),
        patch("main.Config.VALID_SYMBOLS", ["SYMBOL-B"]),
        patch("main.Config.TRAINER_IMAGE", "custom/image:tag"),
    ):
        # Execute
        main()

        # Verify namespace
        call_args = batch_v1_instance.create_namespaced_job.call_args
        assert call_args is not None
        assert call_args[1]["namespace"] == "custom-ns"

        # Verify container image
        container_call_args = mock_k8s_client.V1Container.call_args
        assert container_call_args[1]["image"] == "custom/image:tag"

        # Verify env vars
        env_calls = mock_k8s_client.V1EnvVar.call_args_list
        env_dict = {
            call[1]["name"]: call[1]["value"]
            for call in env_calls
        }
        assert env_dict["SYMBOL"] == "SYMBOL-B"
