#!/bin/bash

install_dir=$(pwd)/install

(
cd openssl

export CROSS_COMPILE=`xcode-select --print-path`/Toolchains/XcodeDefault.xctoolchain/usr/bin/
export CROSS_TOP=`xcode-select --print-path`/Platforms/iPhoneOS.platform/Developer/
export CROSS_SDK=iPhoneOS.sdk
export __CNF_CFLAGS=-fembed-bitcode

./Configure --prefix=$install_dir -no-tests -no-legacy ios64-cross && make -j && make install_sw
)

(
cd libssh

rm -rf build
cmake -H. -Bbuild -DCMAKE_INSTALL_PREFIX=$install_dir -DBUILD_STATIC_LIB=ON -DBUILD_SHARED_LIBS=OFF -DWITH_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release -GXcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_PREFIX_PATH=$install_dir -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
cmake --build build/ --config Release -- CODE_SIGNING_ALLOWED=NO
cmake --install build/
)
