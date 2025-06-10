#!/bin/bash

set -e
set -x

sudo_command="$1"

arch=$(uname -m | sed -e s/aarch64/arm64/)

$sudo_command apt-get update -qq
$sudo_command apt-get install -qq software-properties-common
wget -nv https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/$arch/cuda-ubuntu1804.pin
$sudo_command mv cuda-ubuntu1804.pin /etc/apt/preferences.d/cuda-repository-pin-600

if [[ $arch = x86_64 ]]; then
    key=3bf863cc.pub
elif [[ $arch = arm64 ]]; then
    key=7fa2af80.pub
else
    echo "Unrecognized arch $arch"
    exit 1
fi
$sudo_command apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/$arch/$key
$sudo_command add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/$arch/ /"
$sudo_command apt-get update -qq
$sudo_command apt-get install -qq cuda-compiler-11.6
