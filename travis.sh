#!/bin/bash

set -e
set -x

if [[ "$(uname)" = "Linux" ]]; then
  wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
  sudo add-apt-repository ppa:ubuntu-toolchain-r/test -y
  sudo apt-get update -qq
  sudo apt-get install -qq wget
  if [[ "$LLVM_CONFIG" = "llvm-config-6.0" ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo apt-add-repository -y "deb https://apt.llvm.org/trusty/ llvm-toolchain-trusty-6.0 main"
    sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -qq llvm-6.0-dev clang-6.0 libclang-6.0-dev llvm-6.0-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-6.0:/usr/share/llvm-6.0
  elif [[ "$LLVM_CONFIG" = "llvm-config-5.0" ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo apt-add-repository -y "deb https://apt.llvm.org/trusty/ llvm-toolchain-trusty-5.0 main"
    sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -qq llvm-5.0-dev clang-5.0 libclang-5.0-dev llvm-5.0-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-5.0:/usr/share/llvm-5.0
  elif [[ "$LLVM_CONFIG" = "llvm-config-3.8" ]]; then
    sudo apt-add-repository -y "deb http://apt.llvm.org/trusty/ llvm-toolchain-trusty-3.8 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo bash -c "echo 'Package: *' >> /etc/apt/preferences.d/llvm-600"
    sudo bash -c "echo 'Pin: origin apt.llvm.org' >> /etc/apt/preferences.d/llvm-600"
    sudo bash -c "echo 'Pin-Priority: 600' >> /etc/apt/preferences.d/llvm-600"
    cat /etc/apt/preferences.d/llvm-600
    apt-cache policy llvm-3.8-dev
    sudo apt-get install -qq llvm-3.8-dev clang-3.8 libclang-3.8-dev llvm-3.8-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/share/llvm-3.8
  else
    sudo apt-get install -qq llvm-3.5-dev clang-3.5 libclang-3.5-dev
  fi
fi

if [[ "$(uname)" = "Darwin" ]]; then
  if [[ "$LLVM_CONFIG" = "llvm-config-6.0" ]]; then
    curl -O http://releases.llvm.org/6.0.0/clang+llvm-6.0.0-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-6.0.0-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-6.0.0-x86_64-apple-darwin/bin/llvm-config llvm-config-6.0
    ln -s clang+llvm-6.0.0-x86_64-apple-darwin/bin/clang clang-6.0
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-6.0.0-x86_64-apple-darwin
  elif [[ "$LLVM_CONFIG" = "llvm-config-5.0" ]]; then
    curl -O http://releases.llvm.org/5.0.1/clang+llvm-5.0.1-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-5.0.1-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-5.0.1-final-x86_64-apple-darwin/bin/llvm-config llvm-config-5.0
    ln -s clang+llvm-5.0.1-final-x86_64-apple-darwin/bin/clang clang-5.0
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-5.0.1-final-x86_64-apple-darwin
  elif [[ "$LLVM_CONFIG" = "llvm-config-3.8" ]]; then
    curl -O http://releases.llvm.org/3.8.0/clang+llvm-3.8.0-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-3.8.0-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-3.8.0-x86_64-apple-darwin/bin/llvm-config llvm-config-3.8
    ln -s clang+llvm-3.8.0-x86_64-apple-darwin/bin/clang clang-3.8
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-3.8.0-x86_64-apple-darwin
  else
    curl -O http://releases.llvm.org/3.5.2/clang+llvm-3.5.2-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-3.5.2-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-3.5.2-x86_64-apple-darwin/bin/llvm-config llvm-config-3.5
    ln -s clang+llvm-3.5.2-x86_64-apple-darwin/bin/clang clang-3.5
  fi

  export PATH=$PWD:$PATH
fi

if [[ $USE_CMAKE -eq 1 ]]; then
  CMAKE_FLAGS=()
  if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
    CMAKE_FLAGS+=(
      -DTERRA_STATIC_LINK_LLVM=OFF
    )
  fi
  if [[ -n $SLIB_INCLUDE_LLVM && $SLIB_INCLUDE_LLVM -eq 0 ]]; then
    CMAKE_FLAGS+=(
      -DTERRA_SLIB_INCLUDE_LLVM=OFF
    )
  fi
  if [[ -n $STATIC_LUAJIT && $STATIC_LUAJIT -eq 0 ]]; then
    CMAKE_FLAGS+=(
      -DTERRA_STATIC_LINK_LUAJIT=OFF
    )
  fi
  if [[ -n $SLIB_INCLUDE_LUAJIT && $SLIB_INCLUDE_LUAJIT -eq 0 ]]; then
    CMAKE_FLAGS+=(
      -DTERRA_SLIB_INCLUDE_LUAJIT=OFF
    )
  fi

  pushd build
  cmake .. -DCMAKE_INSTALL_PREFIX=$PWD/../install "${CMAKE_FLAGS[@]}"
  make install -j2
  ctest -j2 || (test "$(uname)" = "Darwin" && test "$LLVM_CONFIG" = "llvm-config-3.8")
  popd

  pushd tests
  ../install/bin/terra ./run
  popd
else
  make LLVM_CONFIG=$(which $LLVM_CONFIG) CLANG=$(which $CLANG) test
fi
