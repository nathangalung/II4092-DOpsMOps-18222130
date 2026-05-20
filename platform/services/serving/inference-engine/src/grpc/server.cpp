#include "server.hpp"
#include <iostream>
#include <chrono>

namespace ml {

InferenceServiceImpl::InferenceServiceImpl(std::shared_ptr<OnnxInference> inference)
    : inference_(inference)
    , start_time_(std::chrono::steady_clock::now()) {}

grpc::Status InferenceServiceImpl::Predict(
    grpc::ServerContext* context,
    const inference::InferenceRequest* request,
    inference::InferenceResponse* response) {

    auto start = std::chrono::high_resolution_clock::now();

    // Convert features from proto to vector
    std::vector<float> features(request->features().begin(), request->features().end());

    // Run inference
    auto result = inference_->Infer(features);

    auto end = std::chrono::high_resolution_clock::now();
    auto latency_us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();

    // Update metrics
    inference_count_++;
    {
        std::lock_guard<std::mutex> lock(latency_mutex_);
        total_latency_us_ += latency_us;
    }

    // Set response
    response->set_prediction(result.prediction);
    response->set_confidence(result.confidence);
    response->set_direction(result.prediction > 0 ? "UP" : "DOWN");
    response->set_latency_us(latency_us);

    return grpc::Status::OK;
}

grpc::Status InferenceServiceImpl::BatchPredict(
    grpc::ServerContext* context,
    const inference::BatchInferenceRequest* request,
    inference::BatchInferenceResponse* response) {

    for (const auto& req : request->requests()) {
        auto* resp = response->add_responses();

        auto start = std::chrono::high_resolution_clock::now();

        std::vector<float> features(req.features().begin(), req.features().end());
        auto result = inference_->Infer(features);

        auto end = std::chrono::high_resolution_clock::now();
        auto latency_us = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();

        inference_count_++;
        {
            std::lock_guard<std::mutex> lock(latency_mutex_);
            total_latency_us_ += latency_us;
        }

        resp->set_prediction(result.prediction);
        resp->set_confidence(result.confidence);
        resp->set_direction(result.prediction > 0 ? "UP" : "DOWN");
        resp->set_latency_us(latency_us);
    }

    return grpc::Status::OK;
}

grpc::Status InferenceServiceImpl::GetModelInfo(
    grpc::ServerContext* context,
    const inference::ModelInfoRequest* request,
    inference::ModelInfoResponse* response) {

    auto info = inference_->GetModelInfo();

    response->set_name(info.name);
    response->set_version(info.version);
    response->set_framework("ONNX Runtime");
    response->set_loaded_at(std::chrono::duration_cast<std::chrono::seconds>(
        start_time_.time_since_epoch()).count());
    response->set_inference_count(inference_count_.load());

    auto count = inference_count_.load();
    double avg_latency;
    {
        std::lock_guard<std::mutex> lock(latency_mutex_);
        avg_latency = count > 0 ? total_latency_us_ / count : 0.0;
    }
    response->set_avg_latency_us(avg_latency);

    return grpc::Status::OK;
}

grpc::Status InferenceServiceImpl::Health(
    grpc::ServerContext* context,
    const common::HealthRequest* request,
    common::HealthResponse* response) {

    auto now = std::chrono::steady_clock::now();
    auto uptime = std::chrono::duration_cast<std::chrono::seconds>(now - start_time_).count();

    response->set_status("SERVING");
    response->set_version("1.0.0");
    response->set_uptime_seconds(uptime);

    return grpc::Status::OK;
}

InferenceServer::InferenceServer(std::shared_ptr<OnnxInference> inference, int port)
    : inference_(inference)
    , port_(port) {}

void InferenceServer::Run() {
    std::string server_address = "0.0.0.0:" + std::to_string(port_);

    InferenceServiceImpl service(inference_);

    grpc::ServerBuilder builder;
    builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
    builder.RegisterService(&service);

    std::unique_ptr<grpc::Server> server(builder.BuildAndStart());
    std::cout << "Inference gRPC server listening on " << server_address << std::endl;

    server->Wait();
}

} // namespace ml
