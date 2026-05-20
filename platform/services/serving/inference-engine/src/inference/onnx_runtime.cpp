#include "onnx_runtime.hpp"
#include <iostream>
#include <algorithm>
#include <cmath>

namespace ml {

OnnxInference::OnnxInference(const std::string& model_path, bool use_gpu)
    : env_(ORT_LOGGING_LEVEL_WARNING, "inference-engine")
    , memory_info_(Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault))
{
    LoadModel(model_path, use_gpu);
}

void OnnxInference::LoadModel(const std::string& model_path, bool use_gpu) {
    Ort::SessionOptions session_options;
    session_options.SetIntraOpNumThreads(4);
    session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

    // Enable GPU if available
    if (use_gpu) {
        try {
            OrtCUDAProviderOptions cuda_options;
            session_options.AppendExecutionProvider_CUDA(cuda_options);
            std::cout << "Using CUDA execution provider" << std::endl;
        } catch (...) {
            std::cout << "CUDA not available, using CPU" << std::endl;
        }
    }

    // Load model
    session_ = std::make_unique<Ort::Session>(env_, model_path.c_str(), session_options);

    // Set model info
    model_info_.name = model_path;
    model_info_.version = "1.0.0";

    // Get input info
    Ort::AllocatorWithDefaultOptions allocator;
    auto input_name = session_->GetInputNameAllocated(0, allocator);
    input_names_.push_back(strdup(input_name.get()));

    auto input_info = session_->GetInputTypeInfo(0);
    auto input_tensor = input_info.GetTensorTypeAndShapeInfo();
    input_shape_ = input_tensor.GetShape();

    // Get output info
    auto output_name = session_->GetOutputNameAllocated(0, allocator);
    output_names_.push_back(strdup(output_name.get()));

    auto output_info = session_->GetOutputTypeInfo(0);
    auto output_tensor = output_info.GetTensorTypeAndShapeInfo();
    output_shape_ = output_tensor.GetShape();

    std::cout << "Model loaded: " << model_path << std::endl;
}

std::vector<float> OnnxInference::Predict(const std::vector<float>& input) {
    // Create input tensor
    std::vector<int64_t> input_shape = input_shape_;
    input_shape[0] = 1;  // Batch size 1

    size_t input_size = 1;
    for (auto dim : input_shape) input_size *= dim;

    auto input_tensor = Ort::Value::CreateTensor<float>(
        memory_info_,
        const_cast<float*>(input.data()),
        input_size,
        input_shape.data(),
        input_shape.size()
    );

    // Run inference
    auto output_tensors = session_->Run(
        Ort::RunOptions{nullptr},
        input_names_.data(),
        &input_tensor,
        1,
        output_names_.data(),
        1
    );

    // Get output
    float* output_data = output_tensors[0].GetTensorMutableData<float>();
    size_t output_size = 1;
    for (auto dim : output_shape_) output_size *= dim;

    return std::vector<float>(output_data, output_data + output_size);
}

InferenceResult OnnxInference::Infer(const std::vector<float>& input) {
    auto output = Predict(input);

    InferenceResult result;
    result.prediction = output.empty() ? 0.0 : static_cast<double>(output[0]);

    // Calculate confidence using sigmoid of absolute prediction value
    result.confidence = 1.0 / (1.0 + std::exp(-std::abs(result.prediction)));

    return result;
}

std::vector<std::vector<float>> OnnxInference::BatchPredict(
    const std::vector<std::vector<float>>& inputs) {

    std::vector<std::vector<float>> results;
    results.reserve(inputs.size());

    for (const auto& input : inputs) {
        results.push_back(Predict(input));
    }

    return results;
}

} // namespace ml
