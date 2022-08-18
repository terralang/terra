#!/bin/bash

set -e

root_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

echo "######################################################################"
echo "### Docker Build Configuration:"
echo "###   * LLVM: $llvm"
echo "###   * CUDA: $cuda"
echo "###   * Variant: $variant"
echo "###   * Test: $test"
echo "###   * Threads: $threads"
echo "######################################################################"

# Check all the variables are set.
[[ -n $llvm ]]
[[ -n $cuda ]]
[[ -n $variant ]]
[[ -n $test ]]
[[ -n $threads ]]

arch=$(uname -m | sed -e s/ppc64le/powerpc64le/)

packages=(
    build-essential cmake git
)
if [[ $variant = "package" || $variant = "upstream" ]]; then
    packages+=(
        llvm-$llvm-dev libclang-$llvm-dev clang-$llvm
        libedit-dev libncurses5-dev zlib1g-dev
    )
    if [[ $llvm -ge 13 ]]; then
        packages+=(
            libmlir-$llvm-dev
            libpfm4-dev
        )
    fi
elif [[ $variant = "prebuilt" ]]; then
    packages+=(
        wget
    )
else
    echo "Don't know this variant: $variant"
    exit 1
fi
if [[ $cuda -eq 1 ]]; then
    packages+=(
        wget
    )
fi

set -x

apt-get update -qq

if [[ $variant = "upstream" ]]; then
    apt-get install -qq wget software-properties-common apt-transport-https ca-certificates
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
    source /etc/lsb-release
    add-apt-repository -y "deb http://apt.llvm.org/$DISTRIB_CODENAME/ llvm-toolchain-$DISTRIB_CODENAME-$llvm main"
    apt-get update -qq
    echo 'Package: *' >> /etc/apt/preferences.d/llvm-600
    echo 'Pin: origin apt.llvm.org' >> /etc/apt/preferences.d/llvm-600
    echo 'Pin-Priority: 600' >> /etc/apt/preferences.d/llvm-600
fi

apt-get install -qq "${packages[@]}"

if [[ $variant = "prebuilt" ]]; then
    wget -nv https://github.com/terralang/llvm-build/releases/download/llvm-$llvm/clang+llvm-$llvm-$arch-linux-gnu.tar.xz
    tar xf clang+llvm-$llvm-$arch-linux-gnu.tar.xz
    mv clang+llvm-$llvm-$arch-linux-gnu /llvm
    rm clang+llvm-$llvm-$arch-linux-gnu.tar.xz
fi

if [[ $cuda -eq 1 ]]; then
    "$root_dir/install_cuda.sh"
else
    echo "disabled: $root_dir/install_cuda.sh"
fi

cd build
cmake -DCMAKE_PREFIX_PATH=/llvm/install -DCMAKE_INSTALL_PREFIX=/terra_install ..
make install -j$threads

if [[ $test -eq 1 ]]; then
    ctest --output-on-failure -j$threads
else
    echo "disabled: ctest --output-on-failure -j$threads"
fi
