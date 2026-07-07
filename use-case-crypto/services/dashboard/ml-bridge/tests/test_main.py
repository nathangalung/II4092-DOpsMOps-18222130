from collections.abc import Generator
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from main import app
from services import prediction as prediction_module

client = TestClient(app)

# Fixtures


@pytest.fixture
def mock_feast_feature_store() -> Generator[MagicMock]:
    with patch("feast.FeatureStore") as mock:
        yield mock


@pytest.fixture
def mock_httpx_client() -> Generator[MagicMock]:
    with patch("httpx.AsyncClient") as mock:
        yield mock


def _mock_view(name: str, feature_names: list[str]) -> MagicMock:
    """Build a mock Feast FeatureView (online) owning the given feature names.

    MagicMock reserves the ``name`` kwarg, so ``.name`` is set after
    construction on both the view and each feature.
    """
    view = MagicMock()
    view.name = name
    view.online = True
    feats = []
    for fname in feature_names:
        feature = MagicMock()
        feature.name = fname
        feats.append(feature)
    view.features = feats
    return view


# Health Check Tests


def test_health_check() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "latency_us" in data


# Feature Service Tests


def test_get_online_features(mock_feast_feature_store: MagicMock) -> None:
    # Setup Mock
    store_instance = MagicMock()
    mock_feast_feature_store.return_value = store_instance

    # _resolve_refs scans online views to map bare names to "<view>:<name>",
    # so expose a view "features" owning value_1/value_2.
    store_instance.list_feature_views.return_value = [
        _mock_view("features", ["value_1", "value_2"])
    ]

    mock_result = MagicMock()
    mock_result.to_dict.return_value = {
        "symbol": ["SYMBOL-1"],
        "value_1": [100.0],
        "value_2": [1000.0],
    }
    store_instance.get_online_features.return_value = mock_result

    # Execute
    payload = {"symbol": "SYMBOL-1", "features": ["value_1", "value_2"]}
    response = client.post("/api/features/online", json=payload)

    # Verify
    assert response.status_code == 200
    data = response.json()
    assert data["symbol"] == "SYMBOL-1"
    assert data["features"]["value_1"] == 100.0
    assert data["features"]["value_2"] == 1000.0
    assert "timestamp" in data

    # Verify Feast call
    store_instance.get_online_features.assert_called_once()
    call_kwargs = store_instance.get_online_features.call_args[1]
    assert call_kwargs["features"] == [
        "features:value_1",
        "features:value_2",
    ]
    assert call_kwargs["entity_rows"] == [{"symbol": "SYMBOL-1"}]


def test_get_feature_definitions(mock_feast_feature_store: MagicMock) -> None:
    # Setup Mock
    store_instance = MagicMock()
    mock_feast_feature_store.return_value = store_instance

    view_mock = MagicMock()
    view_mock.name = "data_view"
    view_mock.tags = {"owner": "me"}

    feature_mock = MagicMock()
    feature_mock.name = "value_1"
    feature_mock.dtype = "FLOAT"

    view_mock.features = [feature_mock]
    store_instance.list_feature_views.return_value = [view_mock]

    # Execute
    response = client.get("/api/features/definitions")

    # Verify
    assert response.status_code == 200
    data = response.json()
    assert len(data["features"]) == 1
    feat = data["features"][0]
    assert feat["name"] == "value_1"
    assert feat["view"] == "data_view"
    assert feat["dtype"] == "FLOAT"
    assert feat["tags"] == {"owner": "me"}


def test_get_latest_features(
    mock_feast_feature_store: MagicMock,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Configure feature list (the env-based config mechanism)
    monkeypatch.setenv("FEAST_LATEST_FEATURES", "value_a,value_b,indicator_x,indicator_y")

    # Setup Mock
    store_instance = MagicMock()
    mock_feast_feature_store.return_value = store_instance

    # FEAST_LATEST_FEATURES names are bare, so _resolve_refs needs the owning view.
    store_instance.list_feature_views.return_value = [
        _mock_view("features", ["value_a", "value_b", "indicator_x", "indicator_y"])
    ]

    mock_result = MagicMock()
    mock_result.to_dict.return_value = {
        "symbol": ["SYMBOL-2"],
        "features:value_a": [3000.0],
        "features:value_b": [500.0],
        "features:indicator_x": [2900.0],
        "features:indicator_y": [2800.0],
    }
    store_instance.get_online_features.return_value = mock_result

    # Execute
    response = client.get("/api/features/latest/SYMBOL-2")

    # Verify
    assert response.status_code == 200
    data = response.json()
    assert data["symbol"] == "SYMBOL-2"
    assert data["features"]["features:value_a"] == 3000.0


# Metrics Service Tests


@patch("services.metrics.httpx.AsyncClient")
def test_list_models(mock_client_cls: MagicMock) -> None:
    # Setup
    mock_client = AsyncMock()
    mock_client_cls.return_value.__aenter__.return_value = mock_client

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"registered_models": []}
    mock_client.get.return_value = mock_response

    # Execute
    response = client.get("/api/metrics/models")

    # Verify
    assert response.status_code == 200
    assert response.json() == {"registered_models": []}
    mock_client.get.assert_called_with(
        "http://mlflow:5000/api/2.0/mlflow/registered-models/list", timeout=10.0
    )


@patch("services.metrics.httpx.AsyncClient")
def test_get_model_metrics(mock_client_cls: MagicMock) -> None:
    # Setup
    mock_client = AsyncMock()
    mock_client_cls.return_value.__aenter__.return_value = mock_client

    # Mock model response
    model_response = MagicMock()
    model_response.status_code = 200
    model_response.json.return_value = {
        "registered_model": {"latest_versions": [{"version": "1", "run_id": "run123"}]}
    }

    # Mock runs response
    runs_response = MagicMock()
    runs_response.status_code = 200
    runs_response.json.return_value = {
        "run": {
            "data": {
                "metrics": [
                    {"key": "accuracy", "value": 0.95},
                    {"key": "f1_score", "value": 0.94},
                ]
            }
        }
    }

    mock_client.get.side_effect = [model_response, runs_response]

    # Execute
    response = client.get("/api/metrics/models/MyModel/metrics")

    # Verify
    assert response.status_code == 200
    data = response.json()
    assert data["model_name"] == "MyModel"
    assert data["version"] == "1"
    assert data["accuracy"] == 0.95
    assert data["f1_score"] == 0.94


# Prediction Service Tests


@patch("services.prediction.httpx.AsyncClient")
def test_predict(mock_client_cls: MagicMock) -> None:
    # Setup
    mock_client = AsyncMock()
    mock_client_cls.return_value.__aenter__.return_value = mock_client

    # Upstream serving contract is the crypto PredictionResponse shape:
    # predicted_price + signal (the same fields main._run_batch_score reads via
    # pred.get("predicted_price")/pred.get("signal")), NOT the legacy
    # predicted_value/class_label pair.
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "symbol": "SYMBOL-1",
        "predicted_price": 51000.0,
        "signal": "BUY",
        "confidence": 0.85,
        "model_version": "v1",
    }
    mock_client.post.return_value = mock_response

    # Execute
    payload = {"symbol": "SYMBOL-1", "features": {"value_1": 100.0}}
    response = client.post("/api/predictions/predict", json=payload)

    # Verify
    assert response.status_code == 200
    data = response.json()
    assert data["signal"] == "BUY"
    assert data["predicted_price"] == 51000.0

    mock_client.post.assert_called_once()
    args, kwargs = mock_client.post.call_args
    # INFERENCE_URL is a module-level constant bound at import; assert against it
    # rather than a hardcoded host so the test tracks the real default.
    assert args[0] == f"{prediction_module.INFERENCE_URL}/predict"
    assert kwargs["json"]["symbol"] == "SYMBOL-1"
