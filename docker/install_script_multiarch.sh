#!/bin/bash

# because Cirrus gives us ARM containers and not VMs, we have to
# extract the body of Dockerfile.ubuntu-prebuilt-multiarch here

set -e

apt-get update -qq
apt-get install -qq build-essential cmake git python3 wget
wget -nv https://github.com/terralang/llvm-build/releases/download/llvm-$llvm/clang+llvm-$llvm-$arch-linux-gnu.tar.xz
tar xf clang+llvm-$llvm-$arch-linux-gnu.tar.xz
mv clang+llvm-$llvm-$arch-linux-gnu /llvm
rm clang+llvm-$llvm-$arch-linux-gnu.tar.xz
echo "disabled: /terra/docker/install_cuda.sh"
cd build
cmake -DCMAKE_PREFIX_PATH=/llvm/install -DCMAKE_INSTALL_PREFIX=/terra_install ..
make install -j$threads
ctest --output-on-failure -j$threads
