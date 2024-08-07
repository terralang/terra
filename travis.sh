#!/bin/bash

set -e
set -x

if [[ $CHECK_CLANG_FORMAT -eq 1 ]]; then
    if [[ $(uname) = Linux ]]; then
        sudo apt-get install -y clang-format-14
        export PATH="/usr/lib/llvm-14/bin:$PATH"
    else
        exit 1
    fi
    which clang-format

    ./format.sh
    git status
    git diff
    git diff-index --quiet HEAD
    exit 0
fi

if [[ -n $DOCKER_DISTRO ]]; then
    if [[ -n $DOCKER_ARCH ]]; then
        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    fi

    ./docker/build.sh "$DOCKER_DISTRO" "$DOCKER_ARCH" "$DOCKER_LLVM" "$DOCKER_LUA" "$DOCKER_STATIC" "$DOCKER_SLIB" "$DOCKER_CUDA" "$DOCKER_VARIANT" "$DOCKER_TEST"
    exit 0
fi

arch=$(uname -m | sed -e s/arm64/aarch64/)
if [[ $(uname) = Linux ]]; then
  echo "Use Docker for testing build on Linux"
  exit 1

elif [[ $(uname) = Darwin ]]; then
  if [[ $LLVM_VERSION = 18 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-18.1.7/clang+llvm-18.1.7-${arch}-apple-darwin.tar.xz
    tar xf clang+llvm-18.1.7-${arch}-apple-darwin.tar.xz
    ln -s clang+llvm-18.1.7-${arch}-apple-darwin/bin/llvm-config llvm-config-17
    ln -s clang+llvm-18.1.7-${arch}-apple-darwin/bin/clang clang-17
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-18.1.7-${arch}-apple-darwin
  elif [[ $LLVM_VERSION = 17 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-17.0.5/clang+llvm-17.0.5-${arch}-apple-darwin.tar.xz
    tar xf clang+llvm-17.0.5-${arch}-apple-darwin.tar.xz
    ln -s clang+llvm-17.0.5-${arch}-apple-darwin/bin/llvm-config llvm-config-17
    ln -s clang+llvm-17.0.5-${arch}-apple-darwin/bin/clang clang-17
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-17.0.5-${arch}-apple-darwin
  elif [[ $LLVM_VERSION = 16 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-16.0.3/clang+llvm-16.0.3-${arch}-apple-darwin.tar.xz
    tar xf clang+llvm-16.0.3-${arch}-apple-darwin.tar.xz
    ln -s clang+llvm-16.0.3-${arch}-apple-darwin/bin/llvm-config llvm-config-16
    ln -s clang+llvm-16.0.3-${arch}-apple-darwin/bin/clang clang-16
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-16.0.3-${arch}-apple-darwin
  elif [[ $LLVM_VERSION = 15 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-15.0.2/clang+llvm-15.0.2-${arch}-apple-darwin.tar.xz
    tar xf clang+llvm-15.0.2-${arch}-apple-darwin.tar.xz
    ln -s clang+llvm-15.0.2-${arch}-apple-darwin/bin/llvm-config llvm-config-15
    ln -s clang+llvm-15.0.2-${arch}-apple-darwin/bin/clang clang-15
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-15.0.2-${arch}-apple-darwin
  elif [[ $LLVM_VERSION = 14 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-14.0.6/clang+llvm-14.0.6-${arch}-apple-darwin.tar.xz
    tar xf clang+llvm-14.0.6-${arch}-apple-darwin.tar.xz
    ln -s clang+llvm-14.0.6-${arch}-apple-darwin/bin/llvm-config llvm-config-14
    ln -s clang+llvm-14.0.6-${arch}-apple-darwin/bin/clang clang-14
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-14.0.6-${arch}-apple-darwin
  elif [[ $LLVM_VERSION = 13 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-13.0.1/clang+llvm-13.0.1-${arch}-apple-darwin.tar.xz
    tar xf clang+llvm-13.0.1-${arch}-apple-darwin.tar.xz
    ln -s clang+llvm-13.0.1-${arch}-apple-darwin/bin/llvm-config llvm-config-13
    ln -s clang+llvm-13.0.1-${arch}-apple-darwin/bin/clang clang-13
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-13.0.1-${arch}-apple-darwin
  elif [[ $LLVM_VERSION = 12 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-12.0.1/clang+llvm-12.0.1-${arch}-apple-darwin-macos11.tar.xz
    tar xf clang+llvm-12.0.1-${arch}-apple-darwin-macos11.tar.xz
    ln -s clang+llvm-12.0.1-${arch}-apple-darwin/bin/llvm-config llvm-config-12
    ln -s clang+llvm-12.0.1-${arch}-apple-darwin/bin/clang clang-12
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-12.0.1-${arch}-apple-darwin
  elif [[ $LLVM_VERSION = 11 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-11.1.0/clang+llvm-11.1.0-${arch}-apple-darwin-macos11.tar.xz
    tar xf clang+llvm-11.1.0-${arch}-apple-darwin-macos11.tar.xz
    ln -s clang+llvm-11.1.0-${arch}-apple-darwin/bin/llvm-config llvm-config-11
    ln -s clang+llvm-11.1.0-${arch}-apple-darwin/bin/clang clang-11
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-11.1.0-${arch}-apple-darwin
  else
    echo "Don't know this LLVM version: $LLVM_VERSION"
    exit 1
  fi

  # workaround for https://github.com/terralang/terra/issues/365
  if [[ ! -e /usr/include ]]; then
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  fi

  export PATH=$PWD:$PATH

elif [[ $(uname) = MINGW* ]]; then
  if [[ $LLVM_VERSION = 14 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-14.0.0/clang+llvm-14.0.0-${arch}-windows-msvc17.7z
    7z x -y clang+llvm-14.0.0-${arch}-windows-msvc17.7z
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-14.0.0-${arch}-windows-msvc17
  elif [[ $LLVM_VERSION = 11 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-11.1.0/clang+llvm-11.1.0-${arch}-windows-msvc17.7z
    7z x -y clang+llvm-11.1.0-${arch}-windows-msvc17.7z
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-11.1.0-${arch}-windows-msvc17
  fi

  if [[ $USE_CUDA -eq 1 ]]; then
    curl -L -O https://developer.download.nvidia.com/compute/cuda/11.6.2/local_installers/cuda_11.6.2_511.65_windows.exe
    ./cuda_11.6.2_511.65_windows.exe -s nvcc_11.6 cudart_11.6
    export PATH="$PATH:/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.6/bin"
  fi

  export CMAKE_GENERATOR="Visual Studio 17 2022"
  export CMAKE_GENERATOR_PLATFORM=x64
  export CMAKE_GENERATOR_TOOLSET="host=x64"

elif [[ $(uname) = FreeBSD ]]; then
  # Nothing to do, everything has already been installed
  echo

else
  echo "Don't know how to run tests on this OS: $(uname)"
  exit 1
fi

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
if [[ -n $TERRA_LUA ]]; then
  CMAKE_FLAGS+=(
    -DTERRA_LUA=$TERRA_LUA
  )
fi
if [[ $USE_CUDA -eq 1 ]]; then
  # Terra should autodetect, but force an error if it doesn't work.
  CMAKE_FLAGS+=(
    -DTERRA_ENABLE_CUDA=ON
  )
fi

pushd build
cmake .. -DCMAKE_INSTALL_PREFIX=$PWD/../install "${CMAKE_FLAGS[@]}"
if [[ $(uname) = MINGW* ]]; then
  cmake --build . --target INSTALL --config Release
else
  make install -j${THREADS:-2}
fi

# Skip ctest on Windows; this is currently broken.
if [[ $(uname) != MINGW* ]]; then
  ctest --output-on-failure -j${THREADS:-2}
fi
popd

# Skip this on macOS because it spews too much on Mojave and newer.
if [[ $(uname) != Darwin ]]; then
    pushd tests
    ../install/bin/terra ./run
    popd
fi

# Only deploy builds with LLVM 13 (macOS) and 11 (Windows).
if [[ (( $(uname) == Darwin && $LLVM_VERSION = 18 ) || ( $(uname) == MINGW* && $LLVM_VERSION = 11 && $USE_CUDA -eq 1 )) && $SLIB_INCLUDE_LLVM -eq 1 && $TERRA_LUA = luajit ]]; then
  RELEASE_NAME=terra-`uname | sed -e s/Darwin/OSX/ | sed -e s/MINGW.*/Windows/`-${arch}-`git rev-parse --short HEAD`
  mv install $RELEASE_NAME
  if [[ $(uname) = MINGW* ]]; then
    7z a -t7z $RELEASE_NAME.7z $RELEASE_NAME
  else
    tar cfJv $RELEASE_NAME.tar.xz $RELEASE_NAME
  fi
  mv $RELEASE_NAME install
fi
