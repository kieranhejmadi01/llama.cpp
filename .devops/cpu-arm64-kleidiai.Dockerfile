ARG UBUNTU_VERSION=24.04

FROM ubuntu:$UBUNTU_VERSION AS build

ARG TARGETARCH
ARG CPU_C_FLAGS="-O3 -march=armv8.6-a+dotprod+bf16+i8mm -mtune=native -fopenmp"
ARG CPU_CXX_FLAGS="-O3 -march=armv8.6-a+dotprod+bf16+i8mm -mtune=native -fopenmp"

RUN apt-get update && \
    apt-get install -y gcc-14 g++-14 build-essential git cmake libssl-dev

ENV CC=gcc-14 CXX=g++-14

WORKDIR /app

COPY . .

RUN if [ "$TARGETARCH" = "arm64" ]; then \
        cmake -S . -B build \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_C_FLAGS="$CPU_C_FLAGS" \
            -DCMAKE_CXX_FLAGS="$CPU_CXX_FLAGS" \
            -DLLAMA_BUILD_TESTS=ON \
            -DLLAMA_BUILD_TOOLS=ON \
            -DGGML_CPU_KLEIDIAI=ON \
            -DGGML_NATIVE=OFF \
            -DGGML_BACKEND_DL=OFF \
            -DGGML_OPENMP=ON \
            -DGGML_METAL=OFF \
            -DGGML_CUDA=OFF \
            -DGGML_VULKAN=OFF; \
    else \
        echo "Unsupported architecture: $TARGETARCH. This Dockerfile is linux/arm64 only."; \
        exit 1; \
    fi && \
    cmake --build build -j $(nproc)

RUN mkdir -p /app/lib && \
    find build -name "*.so*" -exec cp -P {} /app/lib \;

RUN mkdir -p /app/full \
    && cp build/bin/* /app/full \
    && cp *.py /app/full \
    && cp -r gguf-py /app/full \
    && cp -r requirements /app/full \
    && cp requirements.txt /app/full \
    && cp .devops/tools.sh /app/full/tools.sh

## Base image
FROM ubuntu:24.04 AS base

RUN apt-get update \
    && apt-get install -y libgomp1 curl \
    && apt autoremove -y \
    && apt clean -y \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

COPY --from=build /app/lib/ /app

### Full
FROM base AS full

COPY --from=build /app/full /app

WORKDIR /app

RUN apt-get update \
    && apt-get install -y \
    git \
    python3 \
    python3-pip \
    python3-wheel \
    && pip install --break-system-packages --upgrade setuptools \
    && pip install --break-system-packages -r requirements.txt \
    && apt autoremove -y \
    && apt clean -y \
    && rm -rf /tmp/* /var/tmp/* \
    && find /var/cache/apt/archives /var/lib/apt/lists -not -name lock -type f -delete \
    && find /var/cache -type f -delete

ENTRYPOINT ["/app/tools.sh"]

### Light, CLI only
FROM base AS light

COPY --from=build /app/full/llama-cli /app/full/llama-completion /app

WORKDIR /app

ENTRYPOINT [ "/app/llama-cli" ]

### Server, Server only
FROM base AS server

ENV LLAMA_ARG_HOST=0.0.0.0

COPY --from=build /app/full/llama-server /app

WORKDIR /app

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/app/llama-server" ]
