#pragma once
#include <string>
#include <vector>
#include <memory>
#include <onnxruntime_cxx_api.h>

namespace ml {

struct InferenceResult {
    double prediction;
    double confidence;
};

struct ModelInfo {
    std::string name;
    std::string version;
};

/**
 * ONNX Runtime inference wrapper
 * Optimized for low latency prediction
 */
class OnnxInference {
public:
    OnnxInference(const std::string& model_path, bool use_gpu = false);
    ~OnnxInference() = default;

    // Run inference - returns prediction and confidence
    InferenceResult Infer(const std::vector<float>& input);

    // Run inference - returns raw output
    std::vector<float> Predict(const std::vector<float>& input);

    // Batch inference
    std::vector<std::vector<float>> BatchPredict(
        const std::vector<std::vector<float>>& inputs);

    // Get model info
    ModelInfo GetModelInfo() const { return model_info_; }
    std::vector<int64_t> GetInputShape() const { return input_shape_; }
    std::vector<int64_t> GetOutputShape() const { return output_shape_; }

private:
    Ort::Env env_;
    std::unique_ptr<Ort::Session> session_;
    Ort::MemoryInfo memory_info_;

    std::vector<const char*> input_names_;
    std::vector<const char*> output_names_;
    std::vector<int64_t> input_shape_;
    std::vector<int64_t> output_shape_;
    ModelInfo model_info_;

    void LoadModel(const std::string& model_path, bool use_gpu);
};

} // namespace ml
