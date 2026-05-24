"""Tests for ONNX exporter."""

import tempfile
from collections.abc import Generator
from unittest.mock import MagicMock, patch

import pytest


class TestONNXExporter:
    """Tests for ONNXExporter class."""

    @pytest.fixture
    def exporter(self) -> Generator:
        """Create ONNX exporter instance."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            return ONNXExporter(output_dir=tempfile.mkdtemp())

    def test_init_default_params(self) -> None:
        """Test default initialization."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            exporter = ONNXExporter()
            assert exporter.output_dir is not None
            assert exporter.opset_version == 13

    def test_init_custom_output_dir(self) -> None:
        """Test custom output directory."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            with tempfile.TemporaryDirectory() as tmpdir:
                exporter = ONNXExporter(output_dir=tmpdir)
                assert exporter.output_dir == tmpdir

    def test_init_custom_opset_version(self) -> None:
        """Test custom opset version."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            exporter = ONNXExporter(opset_version=15)
            assert exporter.opset_version == 15

    def test_export_keras_calls_tf2onnx(self) -> None:
        """Test export_keras calls tf2onnx conversion."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx") as mock_tf2onnx,
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            mock_tf2onnx.convert.from_keras.return_value = (MagicMock(), None)

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            result = exporter.export_keras(mock_model, "test_model.onnx")

            mock_tf2onnx.convert.from_keras.assert_called_once()
            assert result.endswith("test_model.onnx")

    def test_export_keras_validates_output(self) -> None:
        """Test export_keras validates exported model."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx") as mock_tf2onnx,
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            mock_tf2onnx.convert.from_keras.return_value = (MagicMock(), None)

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock(return_value=True)

            mock_model = MagicMock()
            exporter.export_keras(mock_model, "test.onnx", validate=True)

            exporter._validate_onnx.assert_called_once()

    def test_export_keras_skip_validation(self) -> None:
        """Test export_keras can skip validation."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx") as mock_tf2onnx,
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            mock_tf2onnx.convert.from_keras.return_value = (MagicMock(), None)

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            exporter.export_keras(mock_model, "test.onnx", validate=False)

            exporter._validate_onnx.assert_not_called()

    def test_export_xgboost_calls_convert(self) -> None:
        """Test export_xgboost calls onnxmltools conversion."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost") as mock_convert,
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            mock_convert.return_value = MagicMock()

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            result = exporter.export_xgboost(mock_model, "xgb.onnx", n_features=10)

            mock_convert.assert_called_once()
            assert result.endswith("xgb.onnx")

    def test_export_xgboost_with_feature_names(self) -> None:
        """Test export_xgboost adds feature names metadata."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost") as mock_convert,
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            mock_onnx_model = MagicMock()
            mock_onnx_model.metadata_props = []
            mock_convert.return_value = mock_onnx_model

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            exporter.export_xgboost(
                mock_model,
                "xgb.onnx",
                n_features=3,
                feature_names=["feat1", "feat2", "feat3"],
            )

            # Should add metadata for feature names
            assert len(mock_onnx_model.metadata_props) == 1

    def test_validate_onnx_checks_model(self) -> None:
        """Test _validate_onnx checks model structure."""
        with (
            patch("src.exporter.onnx") as mock_onnx,
            patch("src.exporter.ort") as mock_ort,
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            mock_session = MagicMock()
            mock_input = MagicMock()
            mock_input.name = "input"
            mock_input.shape = [1, 10]
            mock_session.get_inputs.return_value = [mock_input]
            mock_ort.InferenceSession.return_value = mock_session

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            result = exporter._validate_onnx("/path/to/model.onnx")

            mock_onnx.load.assert_called_once()
            mock_onnx.checker.check_model.assert_called_once()
            assert result is True

    def test_export_and_log_to_mlflow_keras(self) -> None:
        """Test export_and_log_to_mlflow for keras model."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx") as mock_tf2onnx,
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow") as mock_mlflow,
        ):
            from src.exporter import ONNXExporter

            mock_tf2onnx.convert.from_keras.return_value = (MagicMock(), None)

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            exporter.export_and_log_to_mlflow(mock_model, "keras", "model.onnx")

            mock_mlflow.log_artifact.assert_called_once()

    def test_export_and_log_to_mlflow_xgboost(self) -> None:
        """Test export_and_log_to_mlflow for xgboost model."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost") as mock_convert,
            patch("src.exporter.mlflow") as mock_mlflow,
        ):
            from src.exporter import ONNXExporter

            mock_convert.return_value = MagicMock()

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            exporter.export_and_log_to_mlflow(
                mock_model, "xgboost", "model.onnx", n_features=10
            )

            mock_mlflow.log_artifact.assert_called_once()

    def test_export_and_log_xgboost_requires_n_features(self) -> None:
        """Test export_and_log_to_mlflow raises error without n_features for xgboost."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())

            mock_model = MagicMock()
            with pytest.raises(ValueError, match="n_features required"):
                exporter.export_and_log_to_mlflow(mock_model, "xgboost", "model.onnx")

    def test_export_model_dispatches_xgboost(self) -> None:
        """Test export_model dispatches to convert_xgboost for xgboost type."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost") as mock_convert,
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            mock_convert.return_value = MagicMock()

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            result = exporter.export_model(
                mock_model,
                "xgboost",
                "model.onnx",
                n_features=10,
            )

            mock_convert.assert_called_once()
            assert result.endswith("model.onnx")

    def test_export_model_dispatches_sklearn(self) -> None:
        """Test export_model dispatches to skl2onnx for sklearn types."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
            patch("skl2onnx.convert_sklearn") as mock_sklearn_convert,
        ):
            from src.exporter import ONNXExporter

            mock_sklearn_convert.return_value = MagicMock()

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())
            exporter._validate_onnx = MagicMock()

            mock_model = MagicMock()
            result = exporter.export_model(
                mock_model,
                "random_forest",
                "rf.onnx",
                n_features=5,
            )

            mock_sklearn_convert.assert_called_once()
            assert result.endswith("rf.onnx")

    def test_export_and_log_requires_n_features_for_any_sklearn(self) -> None:
        """Test export_and_log_to_mlflow raises error without n_features for any non-keras model."""
        with (
            patch("src.exporter.onnx"),
            patch("src.exporter.ort"),
            patch("src.exporter.tf2onnx"),
            patch("src.exporter.convert_xgboost"),
            patch("src.exporter.mlflow"),
        ):
            from src.exporter import ONNXExporter

            exporter = ONNXExporter(output_dir=tempfile.mkdtemp())

            mock_model = MagicMock()
            with pytest.raises(ValueError, match="n_features required"):
                exporter.export_and_log_to_mlflow(
                    mock_model,
                    "lightgbm",
                    "model.onnx",
                )


class TestGetModelInfo:
    """Tests for get_model_info function."""

    def test_get_model_info_returns_dict(self) -> None:
        """Test get_model_info returns model information."""
        with patch("src.exporter.onnx") as mock_onnx:
            from src.exporter import get_model_info

            # Mock ONNX model structure
            mock_model = MagicMock()
            mock_model.opset_import = [MagicMock(version=13)]
            mock_model.producer_name = "test_producer"

            # Mock input
            mock_input = MagicMock()
            mock_input.name = "input"
            mock_dim = MagicMock()
            mock_dim.dim_value = 10
            mock_input.type.tensor_type.shape.dim = [MagicMock(dim_value=-1), mock_dim]
            mock_input.type.tensor_type.elem_type = 1  # FLOAT

            # Mock output
            mock_output = MagicMock()
            mock_output.name = "output"
            mock_output.type.tensor_type.shape.dim = [
                MagicMock(dim_value=-1),
                MagicMock(dim_value=1),
            ]
            mock_output.type.tensor_type.elem_type = 1

            mock_model.graph.input = [mock_input]
            mock_model.graph.output = [mock_output]
            mock_model.graph.node = [MagicMock()] * 10

            mock_onnx.load.return_value = mock_model
            mock_onnx.TensorProto.DataType.Name.return_value = "FLOAT"

            info = get_model_info("/path/to/model.onnx")

            assert "opset_version" in info
            assert "producer" in info
            assert "inputs" in info
            assert "outputs" in info
            assert "num_nodes" in info
            assert info["num_nodes"] == 10
