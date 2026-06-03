#!/bin/bash

set -e

# Optional: Import test library
source dev-container-features-test-lib

check "cuda version" test -d /usr/local/cuda-13.0

# Check installation of cuda-libraries
check "libcudart.so" test 1 -eq "$(find /usr -name 'libcudart.so' | wc -l)"
check "libcublas.so" test 1 -eq "$(find /usr -name 'libcublas.so' | wc -l)"
check "libcublasLt.so" test 1 -eq "$(find /usr -name 'libcublasLt.so' | wc -l)"
check "libcufft.so" test 1 -eq "$(find /usr -name 'libcufft.so' | wc -l)"
check "libcurand.so" test 1 -eq "$(find /usr -name 'libcurand.so' | wc -l)"
check "libcusolver.so" test 1 -eq "$(find /usr -name 'libcusolver.so' | wc -l)"
check "libcusparse.so" test 1 -eq "$(find /usr -name 'libcusparse.so' | wc -l)"

# Report result
reportResults