#!/bin/bash

set -e
set -x

sudo_command="$1"

$sudo_command apt-get update -qq
$sudo_command apt-get install -qq software-properties-common
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin
mv cuda-ubuntu1804.pin /etc/apt/preferences.d/cuda-repository-pin-600
$sudo_command apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
$sudo_command add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/ /"
$sudo_command apt-get update -qq
$sudo_command apt-get install -qq cuda-toolkit-11.6
