FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev kmod cpio rsync \
    gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu clang lld llvm \
    device-tree-compiler mkbootimg android-sdk-libsparse-utils \
    lz4 xz-utils unzip zip e2fsprogs erofs-utils file git ca-certificates \
    python3 python3-pip wget curl sudo fakeroot qemu-user-static binfmt-support
WORKDIR /work
