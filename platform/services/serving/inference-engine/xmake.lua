-- Inference Engine build configuration (Xmake + Mold)

set_project("inference-engine")
set_version("1.0.0")
set_xmakever("2.9.0")

-- C++17 standard
set_languages("c++17")

-- Use mold linker for faster linking (if available)
add_ldflags("-fuse-ld=mold", {force = true})

-- Release mode flags
if is_mode("release") then
    set_optimize("fastest")       -- -O3
    add_defines("NDEBUG")
end

-- ONNX Runtime configuration
local onnxruntime_root = os.getenv("ONNXRUNTIME_ROOT") or "/opt/onnxruntime"

-- Proto output directory
local proto_out_dir = path.join(os.projectdir(), "build", "generated")

-- Main inference engine binary
target("inference-engine")
    set_kind("binary")

    -- Application sources
    add_files("src/main.cpp", "src/inference/onnx_runtime.cpp", "src/grpc/server.cpp")

    add_includedirs("src", proto_out_dir, path.join(onnxruntime_root, "include"))
    add_linkdirs(path.join(onnxruntime_root, "lib"))
    add_links("onnxruntime")
    add_syslinks("pthread")

    -- Resolve system grpc++ and protobuf via pkg-config at load time
    on_load(function(target)
        local cflags = os.iorunv("pkg-config", {"--cflags", "grpc++", "protobuf"}):trim()
        for flag in cflags:gmatch("%S+") do
            if flag:startswith("-I") then
                target:add("includedirs", flag:sub(3))
            end
        end
        local ldflags = os.iorunv("pkg-config", {"--libs", "grpc++", "protobuf"}):trim()
        target:add("ldflags", ldflags, {force = true})
    end)

    -- Generate protobuf/gRPC sources and add them to the build at config time.
    -- on_config runs after script parsing and on_load, but before file resolution
    -- and compilation — the proper xmake lifecycle hook for code generation.
    on_config(function(target)
        local proto_dir = path.join(os.projectdir(), "proto")

        os.mkdir(proto_out_dir)

        -- Generate common.proto → common.pb.h, common.pb.cc
        os.runv("protoc", {
            "--cpp_out=" .. proto_out_dir,
            "-I" .. proto_dir,
            path.join(proto_dir, "common.proto")
        })

        -- Generate inference.proto → inference.pb.{h,cc} + inference.grpc.pb.{h,cc}
        local grpc_plugin = os.iorunv("which", {"grpc_cpp_plugin"}):trim()
        os.runv("protoc", {
            "--cpp_out=" .. proto_out_dir,
            "--grpc_out=" .. proto_out_dir,
            "--plugin=protoc-gen-grpc=" .. grpc_plugin,
            "-I" .. proto_dir,
            path.join(proto_dir, "inference.proto")
        })

        -- Add all generated .cc files as sources for compilation
        for _, filepath in ipairs(os.files(path.join(proto_out_dir, "*.cc"))) do
            target:add("files", filepath)
        end
    end)

    -- Install
    on_install(function(target)
        os.cp(target:targetfile(), path.join(target:installdir(), "bin", "inference-engine"))
    end)

-- Test target (optional)
option("tests")
    set_default(false)
    set_description("Build test executables")
option_end()

if has_config("tests") then
    target("test_inference")
        set_kind("binary")
        add_files("tests/test_inference.cpp")
        add_includedirs("src")
        add_syslinks("pthread")
end
