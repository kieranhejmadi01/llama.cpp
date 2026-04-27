# CPU-only ARM64 KleidiAI Docker builds

This image is a source-built `linux/arm64` llama.cpp image for CPU-only Arm systems based on `ubuntu:24.04`. It explicitly enables KleidiAI with `-DGGML_CPU_KLEIDIAI=ON`, disables dynamic backend loading, and keeps the same multi-stage target layout as `.devops/cpu.Dockerfile`: `build`, `base`, `full`, `light`, and `server`.

## Differences from `.devops/cpu.Dockerfile`

- Builds only for `linux/arm64`.
- Enables KleidiAI explicitly with `-DGGML_CPU_KLEIDIAI=ON`.
- Does not use `-DGGML_CPU_ALL_VARIANTS=ON`; the selected CPU profile comes from the build-arg compiler flags.
- Disables dynamic backend loading with `-DGGML_BACKEND_DL=OFF`.
- Disables GPU-oriented backends with `-DGGML_METAL=OFF`, `-DGGML_CUDA=OFF`, and `-DGGML_VULKAN=OFF`.
- Enables tests and tools with `-DLLAMA_BUILD_TESTS=ON` and `-DLLAMA_BUILD_TOOLS=ON` so the build has validation binaries available.
- Sets explicit C and C++ CPU flags through `CPU_C_FLAGS` and `CPU_CXX_FLAGS`.

## Apple M3 default

The default build args are tuned for Apple M3-class Arm CPUs without assuming SVE or SVE2:

```sh
CPU_C_FLAGS="-O3 -march=armv8.6-a+dotprod+bf16+i8mm -mtune=native -fopenmp"
CPU_CXX_FLAGS="-O3 -march=armv8.6-a+dotprod+bf16+i8mm -mtune=native -fopenmp"
```

SVE2 is intentionally omitted from the default. If the target CPU does not advertise SVE or SVE2, building SVE2 instructions into the image can produce binaries that fail with illegal instruction errors. `+dotprod` is spelled out even though it is part of the Armv8.6 profile so llama.cpp's KleidiAI CMake logic includes the matching dot-product microkernel sources.

Build the default `full` image:

```sh
docker buildx build \
  --platform linux/arm64 \
  --target full \
  -f .devops/cpu-arm64-kleidiai.Dockerfile \
  -t kiehej01/llama.cpp:full-m3-kleidiai .
```

Build the `light` image:

```sh
docker buildx build \
  --platform linux/arm64 \
  --target light \
  -f .devops/cpu-arm64-kleidiai.Dockerfile \
  -t kiehej01/llama.cpp:light-m3-kleidiai .
```

Build the `server` image:

```sh
docker buildx build \
  --platform linux/arm64 \
  --target server \
  -f .devops/cpu-arm64-kleidiai.Dockerfile \
  -t kiehej01/llama.cpp:server-m3-kleidiai .
```

## NVIDIA Grace retargeting

Grace uses the same Dockerfile with build-arg overrides:

```sh
docker buildx build \
  --platform linux/arm64 \
  --target full \
  -f .devops/cpu-arm64-kleidiai.Dockerfile \
  --build-arg CPU_C_FLAGS="-O3 -march=armv9-a+dotprod+sve2+bf16+i8mm -mtune=neoverse-v2 -fopenmp" \
  --build-arg CPU_CXX_FLAGS="-O3 -march=armv9-a+dotprod+sve2+bf16+i8mm -mtune=neoverse-v2 -fopenmp" \
  -t kiehej01/llama.cpp:full-grace-kleidiai .
```

Use the same build args with `--target light` or `--target server` to produce the smaller Grace images.

## Experimental Apple M3 SVE2 profile

This command uses the exact ARMv9/SVE2 profile requested for experimentation. It may not run on M3 if SVE2 is unavailable on the host CPU.

```sh
docker buildx build \
  --platform linux/arm64 \
  --target full \
  -f .devops/cpu-arm64-kleidiai.Dockerfile \
  --build-arg CPU_C_FLAGS="-O3 -march=armv9-a+dotprod+sve2+bf16+i8mm -mtune=native -fopenmp" \
  --build-arg CPU_CXX_FLAGS="-O3 -march=armv9-a+dotprod+sve2+bf16+i8mm -mtune=native -fopenmp" \
  -t kiehej01/llama.cpp:full-m3-sve2-kleidiai .
```

## Smoke checks

After building the default full image:

```sh
docker run --rm --entrypoint /app/llama-cli kiehej01/llama.cpp:full-m3-kleidiai --help
docker run --rm --entrypoint /app/llama-bench kiehej01/llama.cpp:full-m3-kleidiai --help
```

If you run tests inside the build container or in a local build tree:

```sh
ctest --test-dir build --output-on-failure
```

## Runtime verification

Run a GGUF model and check the startup log for `CPU_KLEIDIAI`:

```sh
docker run --rm \
  -v /path/to/models:/models \
  --entrypoint /app/llama-cli \
  kiehej01/llama.cpp:full-m3-kleidiai \
  -m /models/model.gguf -p "Hello" -n 16 2>&1 | grep CPU_KLEIDIAI
```

Capture a baseline with `llama-bench`:

```sh
docker run --rm \
  -v /path/to/models:/models \
  --entrypoint /app/llama-bench \
  kiehej01/llama.cpp:full-m3-kleidiai \
  -m /models/model.gguf
```
