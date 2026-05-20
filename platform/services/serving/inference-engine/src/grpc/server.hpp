#pragma once
#include <memory>
#include <string>
#include <atomic>
#include <chrono>
#include <mutex>
#include <grpcpp/grpcpp.h>
#include "inference.grpc.pb.h"
#include "../inference/onnx_runtime.hpp"

namespace ml {

class InferenceServiceImpl final : public inference::InferenceEngine::Service {
public:
    explicit InferenceServiceImpl(std::shared_ptr<OnnxInference> inference);

    grpc::Status Predict(
        grpc::ServerContext* context,
        const inference::InferenceRequest* request,
        inference::InferenceResponse* response) override;

    grpc::Status BatchPredict(
        grpc::ServerContext* context,
        const inference::BatchInferenceRequest* request,
        inference::BatchInferenceResponse* response) override;

    grpc::Status GetModelInfo(
        grpc::ServerContext* context,
        const inference::ModelInfoRequest* request,
        inference::ModelInfoResponse* response) override;

    grpc::Status Health(
        grpc::ServerContext* context,
        const common::HealthRequest* request,
        common::HealthResponse* response) override;

private:
    std::shared_ptr<OnnxInference> inference_;
    std::atomic<int64_t> inference_count_{0};
    double total_latency_us_{0.0};
    mutable std::mutex latency_mutex_;
    std::chrono::steady_clock::time_point start_time_;
};

class InferenceServer final {
public:
    InferenceServer(std::shared_ptr<OnnxInference> inference, int port);
    void Run();

private:
    std::shared_ptr<OnnxInference> inference_;
    int port_;
};

} // namespace ml
