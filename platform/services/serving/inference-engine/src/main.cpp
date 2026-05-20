/**
 * C++ ONNX Runtime inference engine
 * Ultra-low latency: <1ms inference
 */
#include <iostream>
#include <memory>
#include <string>
#include <thread>
#include "inference/onnx_runtime.hpp"
#include "grpc/server.hpp"

int main(int argc, char** argv) {
    std::cout << "Starting inference engine" << std::endl;
    
    // Config from environment
    std::string model_path = std::getenv("MODEL_PATH") ? 
        std::getenv("MODEL_PATH") : "/app/models/model.onnx";
    int grpc_port = std::getenv("GRPC_PORT") ? 
        std::atoi(std::getenv("GRPC_PORT")) : 50052;
    bool use_gpu = std::getenv("USE_GPU") ? 
        std::string(std::getenv("USE_GPU")) == "true" : false;
    
    // Initialize ONNX Runtime
    auto inference = std::make_shared<ml::OnnxInference>(model_path, use_gpu);

    // Start gRPC server
    ml::InferenceServer server(inference, grpc_port);
    server.Run();
    
    return 0;
}
