#!/bin/bash

set -e
set -x

if [[ $CHECK_CLANG_FORMAT -eq 1 ]]; then
    if [[ $(uname) = Linux ]]; then
        wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
        sudo add-apt-repository -y "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-9 main"
        for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
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
    ./docker/build.sh $DOCKER_BUILD
    exit 0
fi

if [[ $(uname) = Linux ]]; then
  sudo apt-get update -qq
  if [[ $LLVM_CONFIG = llvm-config-11 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-11 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-11-dev clang-11 libclang-11-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-11:/usr/share/llvm-11
    if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/llvm-11/lib"
    fi
  elif [[ $LLVM_CONFIG = llvm-config-10 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-10 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-10-dev clang-10 libclang-10-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-10:/usr/share/llvm-10
    if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/llvm-10/lib"
    fi
  elif [[ $LLVM_CONFIG = llvm-config-9 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-9 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-9-dev clang-9 libclang-9-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-9:/usr/share/llvm-9
    if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/llvm-9/lib"
    fi
  elif [[ $LLVM_CONFIG = llvm-config-8 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-8 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-8-dev clang-8 libclang-8-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-8:/usr/share/llvm-8
    if [[ -n $STATIC_LLVM && $STATIC_LLVM -eq 0 ]]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/llvm-8/lib"
    fi
  elif [[ $LLVM_CONFIG = llvm-config-7 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-7 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo apt-get install -y llvm-7-dev clang-7 libclang-7-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-7:/usr/share/llvm-7
  elif [[ $LLVM_CONFIG = llvm-config-6.0 ]]; then
    sudo apt-get install -qq llvm-6.0-dev clang-6.0 libclang-6.0-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-6.0:/usr/share/llvm-6.0
  elif [[ $LLVM_CONFIG = llvm-config-5.0 ]]; then
    sudo apt-get install -qq llvm-5.0-dev clang-5.0 libclang-5.0-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/lib/llvm-5.0:/usr/share/llvm-5.0
  elif [[ $LLVM_CONFIG = llvm-config-3.8 ]]; then
    wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | sudo apt-key add -
    sudo add-apt-repository -y "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-3.8 main"
    for i in {1..5}; do sudo apt-get update -qq && break || sleep 15; done
    sudo bash -c "echo 'Package: *' >> /etc/apt/preferences.d/llvm-600"
    sudo bash -c "echo 'Pin: origin apt.llvm.org' >> /etc/apt/preferences.d/llvm-600"
    sudo bash -c "echo 'Pin-Priority: 600' >> /etc/apt/preferences.d/llvm-600"
    cat /etc/apt/preferences.d/llvm-600
    apt-cache policy llvm-3.8-dev
    # Travis has LLVM pre-installed, and it's on the wrong version...
    sudo apt-get autoremove -y llvm-3.8
    sudo apt-get install -y llvm-3.8-dev clang-3.8 libclang-3.8-dev libedit-dev
    export CMAKE_PREFIX_PATH=/usr/share/llvm-3.8
  else
    sudo apt-get install -qq llvm-3.5-dev clang-3.5 libclang-3.5-dev
  fi

  if [[ $USE_CUDA -eq 1 ]]; then
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_9.2.148-1_amd64.deb
    sudo dpkg -i cuda-repo-ubuntu1604_9.2.148-1_amd64.deb
    sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
    sudo apt-get update -qq
    sudo apt-get install -qq cuda-toolkit-9.2
  fi
fi

if [[ $(uname) = Darwin ]]; then
  if [[ $LLVM_CONFIG = llvm-config-11 ]]; then
    curl -L -O https://github.com/elliottslaughter/llvm-build/releases/download/llvm-11.0.1/clang+llvm-11.0.1-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-11.0.1-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-11.0.1-x86_64-apple-darwin/bin/llvm-config llvm-config-11
    ln -s clang+llvm-11.0.1-x86_64-apple-darwin/bin/clang clang-11
    export CMAKE_PREFIX_PATH=$PWD/clang+llvm-11.0.1-x86_64-apple-darwin
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
    curl -L -O http://releases.llvm.org/3.5.2/clang+llvm-3.5.2-x86_64-apple-darwin.tar.xz
    tar xf clang+llvm-3.5.2-x86_64-apple-darwin.tar.xz
    ln -s clang+llvm-3.5.2-x86_64-apple-darwin/bin/llvm-config llvm-config-3.5
    ln -s clang+llvm-3.5.2-x86_64-apple-darwin/bin/clang clang-3.5
  fi

  if [[ $USE_CUDA -eq 1 ]]; then
    curl -L -o cuda.dmg https://developer.nvidia.com/compute/cuda/9.2/Prod2/local_installers/cuda_9.2.148_mac
    echo "defb095aa002301f01b2f41312c9b1630328847800baa1772fe2bbb811d5fa9f  cuda.dmg" | shasum -c -a 256
    hdiutil attach cuda.dmg
    # This is probably the "correct" way to do it, but it times out on Travis.
    # /Volumes/CUDAMacOSXInstaller/CUDAMacOSXInstaller.app/Contents/MacOS/CUDAMacOSXInstaller --accept-eula --silent --no-window --install-package=cuda-toolkit
    # There is a bug in GNU Tar 1.31 which causes a crash; stick to 1.30 for now.
    brew tap elliottslaughter/tap
    brew install gnu-tar@1.30
    sudo gtar xf /Volumes/CUDAMacOSXInstaller/CUDAMacOSXInstaller.app/Contents/Resources/payload/cuda_mac_installer_tk.tar.gz -C / --no-overwrite-dir --no-same-owner
    hdiutil detach /Volumes/CUDAMacOSXInstaller
  fi

  # workaround for https://github.com/terralang/terra/issues/365
  if [[ ! -e /usr/include ]]; then
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
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
  if [[ -n $TERRA_LUA ]]; then
    CMAKE_FLAGS+=(
      -DTERRA_LUA=$TERRA_LUA
    )
  fi

  pushd build
  cmake .. -DCMAKE_INSTALL_PREFIX=$PWD/../install "${CMAKE_FLAGS[@]}"
  make install -j${THREADS:-2}
  ctest --output-on-failure -j${THREADS:-2}
  popd

  # Skip this on macOS because it spews too much on Mojave and newer.
  if [[ $(uname) != Darwin ]]; then
      pushd tests
      ../install/bin/terra ./run
      popd
  fi

  # Only deploy CMake builds, and only with LLVM 9.
  if [[ $LLVM_CONFIG = llvm-config-9 && $USE_CUDA -eq 1 && $TERRA_LUA = luajit ]]; then
    RELEASE_NAME=terra-`uname | sed -e s/Darwin/OSX/`-`uname -m`-`git rev-parse --short HEAD`
    mv install $RELEASE_NAME
    zip -q -r $RELEASE_NAME.zip $RELEASE_NAME
    mv $RELEASE_NAME install
  fi
else
  make LLVM_CONFIG=$(which $LLVM_CONFIG) CLANG=$(which $CLANG) test -j${THREADS:-2}
fi
