#!/bin/bash

set -e

root_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"

echo "######################################################################"
echo "### Docker Build Configuration:"
echo "###   * LLVM: $llvm"
echo "###   * Lua: ${lua:-(auto)}"
echo "###   * Static: ${static:-(auto)}"
echo "###   * Slib: ${slib:-(auto)}"
echo "###   * CUDA: $cuda"
echo "###   * Variant: $variant"
echo "###   * Test: $test"
echo "###   * Threads: $threads"
echo "######################################################################"

# Check all the variables are set.
[[ -n $llvm ]]
# $lua is optional
# $static is optional
# $slib is optional
[[ -n $cuda ]]
[[ -n $variant ]]
[[ -n $test ]]
[[ -n $threads ]]

arch=$(uname -m | sed -e s/ppc64le/powerpc64le/)

packages=(
    build-essential gdb git wget
)
if [[ $variant = "package" || $variant = "upstream" ]]; then
    packages+=(
        llvm-$llvm-dev libclang-$llvm-dev clang-$llvm
        libncurses-dev libzstd-dev zlib1g-dev
    )
    if [[ $llvm -ge 18 ]]; then
        packages+=(
            libpolly-$llvm-dev
        )
    fi
elif [[ $variant = "prebuilt" ]]; then
    true # no dependencies
else
    echo "Don't know this variant: $variant"
    exit 1
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

# Use an upstream CMake so that we can control the exact version.
wget -nv https://github.com/Kitware/CMake/releases/download/v3.26.4/cmake-3.26.4-linux-$(uname -m).tar.gz
tar xf cmake-3.26.4-linux-$(uname -m).tar.gz
export PATH="$PATH:$PWD/cmake-3.26.4-linux-$(uname -m)/bin"

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

cmake_flags=()
if [[ -n $lua ]]; then
    cmake_flags+=(
        -DTERRA_LUA="$lua"
    )
fi
if [[ -n $static && $static -eq 0 ]]; then
    cmake_flags+=(
      -DTERRA_STATIC_LINK_LLVM=OFF
      -DTERRA_STATIC_LINK_LUAJIT=OFF
    )
fi
if [[ -n $slib && $slib -eq 0 ]]; then
    cmake_flags+=(
      -DTERRA_SLIB_INCLUDE_LLVM=OFF
      -DTERRA_SLIB_INCLUDE_LUAJIT=OFF
    )
fi
if [[ $cuda -eq 1 ]]; then
    # Terra should autodetect, but force an error if it doesn't work.
    cmake_flags+=(
        -DTERRA_ENABLE_CUDA=ON
    )
fi

cd build
cmake -DCMAKE_PREFIX_PATH=/llvm -DCMAKE_INSTALL_PREFIX=/terra_install "${cmake_flags[@]}" ..
make install -j$threads

if [[ $test -eq 1 ]]; then
    ctest --output-on-failure -j$threads
else
    echo "disabled: ctest --output-on-failure -j$threads"
fi
