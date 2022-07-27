#!/bin/bash

set -e
set -x

if [[ $CHECK_CLANG_FORMAT -eq 1 ]]; then
    if [[ $(uname) = Linux ]]; then
        sudo apt-get install -y clang-format-9
        export PATH="/usr/lib/llvm-9/bin:$PATH"
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

if [[ -n $DOCKER_BUILD ]]; then
    if [[ -n $DOCKER_ARCH ]]; then
        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    fi

    variant=
    if [[ $DOCKER_LLVM = "3.8" ]]; then
        variant=upstream
    elif [[ $DOCKER_LLVM = *"."*"."* ]]; then
        variant=prebuilt
    fi
    if [[ -n $DOCKER_ARCH ]]; then
        variant=${variant}${variant:+-}multiarch
    fi
    ./docker/build.sh $DOCKER_BUILD "$DOCKER_ARCH" $DOCKER_LLVM $variant
    exit 0
fi

if [[ $(uname) = Linux ]]; then
  distro_name="$(lsb_release -cs)"
  sudo apt-get update -qq
  if [[ $LLVM_CONFIG = llvm-config-13 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/${distro_name}/ llvm-toolchain-${distro_name}-13 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-13-dev clang-13 libclang-13-dev libedit-dev libpfm4-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-13:/usr/share/llvm-13
    if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/llvm-13/lib"
    fi
  elif [[ $LLVM_CONFIG = llvm-config-12 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/${distro_name}/ llvm-toolchain-${distro_name}-12 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-12-dev clang-12 libclang-12-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-12:/usr/share/llvm-12
    if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/llvm-12/lib"
    fi
  elif [[ $LLVM_CONFIG = llvm-config-11 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/${distro_name}/ llvm-toolchain-${distro_name}-11 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-11-dev clang-11 libclang-11-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-11:/usr/share/llvm-11
    if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/llvm-11/lib"
    fi
  elif [[ $LLVM_CONFIG = llvm-config-10 ]]; then
    sudo apt-get install -y llvm-10-dev clang-10 libclang-10-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-10:/usr/share/llvm-10
  elif [[ $LLVM_CONFIG = llvm-config-9 ]]; then
    sudo apt-get install -y llvm-9-dev clang-9 libclang-9-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-9:/usr/share/llvm-9
  elif [[ $LLVM_CONFIG = llvm-config-8 ]]; then
    sudo apt-get install -y llvm-8-dev clang-8 libclang-8-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-8:/usr/share/llvm-8
  elif [[ $LLVM_CONFIG = llvm-config-7 ]]; then
    sudo apt-get install -y llvm-7-dev clang-7 libclang-7-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-7:/usr/share/llvm-7
  elif [[ $LLVM_CONFIG = llvm-config-6.0 ]]; then
    sudo apt-get install -qq llvm-6.0-dev clang-6.0 libclang-6.0-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-6.0:/usr/share/llvm-6.0
  elif [[ $LLVM_CONFIG = llvm-config-5.0 ]]; then
    sudo apt-get install -qq llvm-5.0-dev clang-5.0 libclang-5.0-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-5.0:/usr/share/llvm-5.0
  else
    echo "Don't know this LLVM version: $LLVM_CONFIG"
    exit 1
  fi

  if [[ $USE_CUDA -eq 1 ]]; then
    ./docker/install_cuda.sh sudo
  fi
fi

if [[ $(uname) = Darwin ]]; then
  if [[ $LLVM_CONFIG = llvm-config-14 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-14.0.6/clang+llvm-14.0.6-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-14.0.6-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-14.0.6-x86_64-apple-darwin/bin/llvm-config llvm-config-14
    ln -s clang+llvm-14.0.6-x86_64-apple-darwin/bin/clang clang-14
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-14.0.6-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-13 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-13.0.1/clang+llvm-13.0.1-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-13.0.1-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-13.0.1-x86_64-apple-darwin/bin/llvm-config llvm-config-13
    ln -s clang+llvm-13.0.1-x86_64-apple-darwin/bin/clang clang-13
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-13.0.1-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-12 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-12.0.1/clang+llvm-12.0.1-x86_64-apple-darwin-macos11.tar.xz
    tar xf clang+llvm-12.0.1-x86_64-apple-darwin-macos11.tar.xz
    ln -s clang+llvm-12.0.1-x86_64-apple-darwin/bin/llvm-config llvm-config-12
    ln -s clang+llvm-12.0.1-x86_64-apple-darwin/bin/clang clang-12
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-12.0.1-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-11 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-11.1.0/clang+llvm-11.1.0-x86_64-apple-darwin-macos11.tar.xz
    tar xf clang+llvm-11.1.0-x86_64-apple-darwin-macos11.tar.xz
    ln -s clang+llvm-11.1.0-x86_64-apple-darwin/bin/llvm-config llvm-config-11
    ln -s clang+llvm-11.1.0-x86_64-apple-darwin/bin/clang clang-11
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-11.1.0-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-10 ]]; then
    curl -L -O https://github.com/llvm/llvm-project/releases/download/llvmorg-10.0.0/clang+llvm-10.0.0-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-10.0.0-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-10.0.0-x86_64-apple-darwin/bin/llvm-config llvm-config-10
    ln -s clang+llvm-10.0.0-x86_64-apple-darwin/bin/clang clang-10
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-10.0.0-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-9 ]]; then
    curl -L -O http://releases.llvm.org/9.0.0/clang+llvm-9.0.0-x86_64-darwin-apple.tar.xz
    tar xf clang+llvm-9.0.0-x86_64-darwin-apple.tar.xz
    ln -s clang+llvm-9.0.0-x86_64-darwin-apple/bin/llvm-config llvm-config-9
    ln -s clang+llvm-9.0.0-x86_64-darwin-apple/bin/clang clang-9
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-9.0.0-x86_64-darwin-apple
  elif [[ $LLVM_CONFIG = llvm-config-8 ]]; then
    curl -L -O http://releases.llvm.org/8.0.0/clang+llvm-8.0.0-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-8.0.0-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-8.0.0-x86_64-apple-darwin/bin/llvm-config llvm-config-8
    ln -s clang+llvm-8.0.0-x86_64-apple-darwin/bin/clang clang-8
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-8.0.0-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-7 ]]; then
    curl -L -O http://releases.llvm.org/7.0.0/clang+llvm-7.0.0-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-7.0.0-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-7.0.0-x86_64-apple-darwin/bin/llvm-config llvm-config-7
    ln -s clang+llvm-7.0.0-x86_64-apple-darwin/bin/clang clang-7
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-7.0.0-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-6.0 ]]; then
    curl -L -O http://releases.llvm.org/6.0.0/clang+llvm-6.0.0-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-6.0.0-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-6.0.0-x86_64-apple-darwin/bin/llvm-config llvm-config-6.0
    ln -s clang+llvm-6.0.0-x86_64-apple-darwin/bin/clang clang-6.0
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-6.0.0-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-5.0 ]]; then
    curl -L -O http://releases.llvm.org/5.0.1/clang+llvm-5.0.1-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-5.0.1-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-5.0.1-final-x86_64-apple-darwin/bin/llvm-config llvm-config-5.0
    ln -s clang+llvm-5.0.1-final-x86_64-apple-darwin/bin/clang clang-5.0
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-5.0.1-final-x86_64-apple-darwin
  elif [[ $LLVM_CONFIG = llvm-config-3.8 ]]; then
    curl -L -O http://releases.llvm.org/3.8.0/clang+llvm-3.8.0-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-3.8.0-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-3.8.0-x86_64-apple-darwin/bin/llvm-config llvm-config-3.8
    ln -s clang+llvm-3.8.0-x86_64-apple-darwin/bin/clang clang-3.8
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-3.8.0-x86_64-apple-darwin
  else
    echo "Don't know this LLVM version: $LLVM_CONFIG"
    exit 1
  fi

  # workaround for https://github.com/terralang/terra/issues/365
  if [[ ! -e /usr/include ]]; then
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  fi

  export PATH=$PWD:$PATH
fi

if [[ $(uname) = MINGW* ]]; then
  if [[ $LLVM_CONFIG = llvm-config-14 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-14.0.0/clang+llvm-14.0.0-x86_64-windows-msvc17.7z
    7z x -y clang+llvm-14.0.0-x86_64-windows-msvc17.7z
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-14.0.0-x86_64-windows-msvc17
  elif [[ $LLVM_CONFIG = llvm-config-11 ]]; then
    curl -L -O https://github.com/terralang/llvm-build/releases/download/llvm-11.1.0/clang+llvm-11.1.0-x86_64-windows-msvc17.7z
    7z x -y clang+llvm-11.1.0-x86_64-windows-msvc17.7z
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-11.1.0-x86_64-windows-msvc17
  fi

  if [[ $USE_CUDA -eq 1 ]]; then
    curl -L -O https://developer.download.nvidia.com/compute/cuda/11.6.2/local_installers/cuda_11.6.2_511.65_windows.exe
    ./cuda_11.6.2_511.65_windows.exe -s nvcc_11.6 cudart_11.6
    export PATH="$PATH:/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.6/bin"
  fi

  export CMAKE_GENERATOR="Visual Studio 17 2022"
  export CMAKE_GENERATOR_PLATFORM=x64
  export CMAKE_GENERATOR_TOOLSET="host=x64"
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

  # Only deploy CMake builds, and only with LLVM 13 (macOS) and 11 (Windows).
  if [[ (( $(uname) == Darwin && $LLVM_CONFIG = llvm-config-13 ) || ( $(uname) == MINGW* && $LLVM_CONFIG = llvm-config-11 && $USE_CUDA -eq 1 )) && $SLIB_INCLUDE_LLVM -eq 1 && $TERRA_LUA = luajit ]]; then
    RELEASE_NAME=terra-`uname | sed -e s/Darwin/OSX/ | sed -e s/MINGW.*/Windows/`-`uname -m`-`git rev-parse --short HEAD`
    mv install $RELEASE_NAME
    if [[ $(uname) = MINGW* ]]; then
      7z a -t7z $RELEASE_NAME.7z $RELEASE_NAME
    else
      tar cfJv $RELEASE_NAME.tar.xz $RELEASE_NAME
    fi
    mv $RELEASE_NAME install
  fi
else
  ${MAKE:-make} LLVM_CONFIG=$(which $LLVM_CONFIG) CLANG=$(which $CLANG) test -j${THREADS:-2}
fi
