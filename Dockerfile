FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LLVM_PATH=/usr

RUN apt-get update && apt-get install -y --no-install-recommends \
        cmake \
        clang \
        clang-tools \
        lld \
        llvm \
        ninja-build \
        rsync \
        git \
        pkg-config \
        ca-certificates \
        dos2unix \
        python3 \
        libx11-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxcursor-dev \
        libxi-dev \
        libxext-dev \
        libgl-dev \
    && rm -rf /var/lib/apt/lists/* \
    # clang-tools 패키지가 /usr/bin/clang-cl 심링크를 생성하지 않으므로 수동으로 만든다
    && ln -sf clang-cl-18 /usr/bin/clang-cl

# ubuntu:24.04 베이스에 이미 UID/GID 1000(`ubuntu` 사용자)이 존재 → 먼저 제거
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g 1000 builder \
    && useradd -m -u 1000 -g 1000 -s /bin/bash builder \
    && mkdir -p /work /build_src \
    && chown -R builder:builder /work /build_src

USER builder
WORKDIR /work

COPY --chown=builder:builder Scripts/Docker/entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["linux", "Debug"]
