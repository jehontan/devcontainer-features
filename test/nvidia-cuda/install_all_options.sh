#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

# Check installation of libcudnn
check "libcudnn.so" test 1 -eq "$(find /usr -name 'libcudnn.so' | wc -l)"

# Check installation of libcudnn9-dev
check "cudnn.h" test 1 -eq "$(find /usr -name 'cudnn.h' | wc -l)"

# Check installation of cuda-nvtx-12-<version>
check "nvtx" test 1 -le "$(find /usr/local -name 'nvtx*' | wc -l)"

# Check installation of cuda-nvcc-12-<version>
check "nvcc" test 1 -le "$(find /usr/local -name 'nvcc*' | wc -l)"

# Check installation of TensorRT
check "libnvinfer.so" test 1 -eq "$(find /usr -name 'libnvinfer.so' | wc -l)"