/**
 * Unit tests for ONNX inference engine
 */
#include <algorithm>
#include <cassert>
#include <cmath>
#include <iostream>
#include <string>
#include <vector>

// Simple test framework
#define TEST(name) void test_##name()
#define ASSERT_EQ(a, b) do { if ((a) != (b)) { std::cerr << "ASSERT_EQ failed: " << #a << " != " << #b << " at line " << __LINE__ << std::endl; exit(1); } } while(0)
#define ASSERT_TRUE(x) do { if (!(x)) { std::cerr << "ASSERT_TRUE failed: " << #x << " at line " << __LINE__ << std::endl; exit(1); } } while(0)
#define ASSERT_FALSE(x) do { if (x) { std::cerr << "ASSERT_FALSE failed: " << #x << " at line " << __LINE__ << std::endl; exit(1); } } while(0)
#define ASSERT_NEAR(a, b, eps) do { if (std::abs((a) - (b)) > (eps)) { std::cerr << "ASSERT_NEAR failed: " << #a << " != " << #b << " at line " << __LINE__ << std::endl; exit(1); } } while(0)
#define RUN_TEST(name) do { std::cout << "Running " << #name << "..." << std::endl; test_##name(); std::cout << "PASSED" << std::endl; } while(0)

// Test vector utilities
TEST(vector_basic_operations) {
    std::vector<float> v1 = {1.0f, 2.0f, 3.0f};
    std::vector<float> v2 = {4.0f, 5.0f, 6.0f};

    ASSERT_EQ(v1.size(), 3);
    ASSERT_EQ(v2.size(), 3);
    ASSERT_EQ(v1[0], 1.0f);
    ASSERT_EQ(v2[2], 6.0f);
}

TEST(vector_resize) {
    std::vector<float> v;
    ASSERT_EQ(v.size(), 0);

    v.resize(10);
    ASSERT_EQ(v.size(), 10);

    v.resize(5);
    ASSERT_EQ(v.size(), 5);
}

TEST(vector_copy) {
    std::vector<float> original = {1.0f, 2.0f, 3.0f};
    std::vector<float> copy = original;

    ASSERT_EQ(original.size(), copy.size());
    for (size_t i = 0; i < original.size(); ++i) {
        ASSERT_EQ(original[i], copy[i]);
    }

    // Modifying copy shouldn't affect original
    copy[0] = 100.0f;
    ASSERT_EQ(original[0], 1.0f);
}

// Test input validation
TEST(input_validation_empty) {
    std::vector<float> empty_input;
    ASSERT_TRUE(empty_input.empty());
}

TEST(input_validation_size) {
    std::vector<float> input(100);
    ASSERT_EQ(input.size(), 100);
}

TEST(input_normalization) {
    std::vector<float> input = {10.0f, 20.0f, 30.0f, 40.0f, 50.0f};

    // Find min and max
    float min_val = *std::min_element(input.begin(), input.end());
    float max_val = *std::max_element(input.begin(), input.end());

    ASSERT_EQ(min_val, 10.0f);
    ASSERT_EQ(max_val, 50.0f);

    // Normalize to [0, 1]
    std::vector<float> normalized(input.size());
    for (size_t i = 0; i < input.size(); ++i) {
        normalized[i] = (input[i] - min_val) / (max_val - min_val);
    }

    ASSERT_NEAR(normalized[0], 0.0f, 0.001f);
    ASSERT_NEAR(normalized[4], 1.0f, 0.001f);
}

// Test batch processing
TEST(batch_creation) {
    std::vector<std::vector<float>> batch;

    for (int i = 0; i < 32; ++i) {
        batch.push_back(std::vector<float>(10, static_cast<float>(i)));
    }

    ASSERT_EQ(batch.size(), 32);
    ASSERT_EQ(batch[0].size(), 10);
    ASSERT_EQ(batch[15][0], 15.0f);
}

TEST(batch_flatten) {
    std::vector<std::vector<float>> batch = {
        {1.0f, 2.0f, 3.0f},
        {4.0f, 5.0f, 6.0f},
    };

    std::vector<float> flat;
    for (const auto& row : batch) {
        flat.insert(flat.end(), row.begin(), row.end());
    }

    ASSERT_EQ(flat.size(), 6);
    ASSERT_EQ(flat[0], 1.0f);
    ASSERT_EQ(flat[3], 4.0f);
}

// Test shape calculations
TEST(shape_calculation_2d) {
    std::vector<int64_t> shape = {32, 10};  // batch_size, features

    int64_t total_elements = 1;
    for (auto dim : shape) {
        total_elements *= dim;
    }

    ASSERT_EQ(total_elements, 320);
}

TEST(shape_calculation_3d) {
    std::vector<int64_t> shape = {1, 24, 10};  // batch, sequence, features

    int64_t total_elements = 1;
    for (auto dim : shape) {
        total_elements *= dim;
    }

    ASSERT_EQ(total_elements, 240);
}

// Test output processing
TEST(output_argmax) {
    std::vector<float> output = {0.1f, 0.7f, 0.2f};  // Probabilities for 3 classes

    int argmax = 0;
    float max_val = output[0];
    for (size_t i = 1; i < output.size(); ++i) {
        if (output[i] > max_val) {
            max_val = output[i];
            argmax = static_cast<int>(i);
        }
    }

    ASSERT_EQ(argmax, 1);  // Second class has highest probability
}

TEST(output_softmax) {
    std::vector<float> logits = {1.0f, 2.0f, 3.0f};
    std::vector<float> probs(logits.size());

    // Compute softmax
    float sum_exp = 0.0f;
    for (float logit : logits) {
        sum_exp += std::exp(logit);
    }

    for (size_t i = 0; i < logits.size(); ++i) {
        probs[i] = std::exp(logits[i]) / sum_exp;
    }

    // Sum of probabilities should be ~1
    float sum = 0.0f;
    for (float p : probs) {
        sum += p;
    }
    ASSERT_NEAR(sum, 1.0f, 0.001f);

    // Highest logit should have highest probability
    ASSERT_TRUE(probs[2] > probs[1]);
    ASSERT_TRUE(probs[1] > probs[0]);
}

// Test error handling
TEST(error_handling_nan) {
    float nan_value = std::numeric_limits<float>::quiet_NaN();
    ASSERT_TRUE(std::isnan(nan_value));
}

TEST(error_handling_inf) {
    float inf_value = std::numeric_limits<float>::infinity();
    ASSERT_TRUE(std::isinf(inf_value));
}

TEST(error_handling_validation) {
    std::vector<float> input = {1.0f, std::numeric_limits<float>::quiet_NaN(), 3.0f};

    bool has_nan = false;
    for (float val : input) {
        if (std::isnan(val)) {
            has_nan = true;
            break;
        }
    }

    ASSERT_TRUE(has_nan);
}

// Test memory management
TEST(memory_allocation) {
    std::vector<float> large_vector;
    large_vector.reserve(1000000);  // Pre-allocate

    ASSERT_TRUE(large_vector.capacity() >= 1000000);
    ASSERT_EQ(large_vector.size(), 0);
}

TEST(memory_clear) {
    std::vector<float> v = {1.0f, 2.0f, 3.0f};
    ASSERT_EQ(v.size(), 3);

    v.clear();
    ASSERT_EQ(v.size(), 0);
}

// Test feature preprocessing
TEST(feature_scaling_standard) {
    // Standard scaling: (x - mean) / std
    std::vector<float> features = {10.0f, 20.0f, 30.0f, 40.0f, 50.0f};

    float mean = 0.0f;
    for (float f : features) mean += f;
    mean /= features.size();

    float var = 0.0f;
    for (float f : features) var += (f - mean) * (f - mean);
    var /= features.size();
    float std_dev = std::sqrt(var);

    ASSERT_NEAR(mean, 30.0f, 0.001f);
    ASSERT_NEAR(std_dev, 14.1421f, 0.01f);

    std::vector<float> scaled(features.size());
    for (size_t i = 0; i < features.size(); ++i) {
        scaled[i] = (features[i] - mean) / std_dev;
    }

    // Scaled values should have mean ~0
    float scaled_mean = 0.0f;
    for (float s : scaled) scaled_mean += s;
    scaled_mean /= scaled.size();
    ASSERT_NEAR(scaled_mean, 0.0f, 0.001f);
}

int main() {
    std::cout << "=== Running Inference Engine Tests ===" << std::endl;

    RUN_TEST(vector_basic_operations);
    RUN_TEST(vector_resize);
    RUN_TEST(vector_copy);
    RUN_TEST(input_validation_empty);
    RUN_TEST(input_validation_size);
    RUN_TEST(input_normalization);
    RUN_TEST(batch_creation);
    RUN_TEST(batch_flatten);
    RUN_TEST(shape_calculation_2d);
    RUN_TEST(shape_calculation_3d);
    RUN_TEST(output_argmax);
    RUN_TEST(output_softmax);
    RUN_TEST(error_handling_nan);
    RUN_TEST(error_handling_inf);
    RUN_TEST(error_handling_validation);
    RUN_TEST(memory_allocation);
    RUN_TEST(memory_clear);
    RUN_TEST(feature_scaling_standard);

    std::cout << "=== All tests passed! ===" << std::endl;
    return 0;
}
