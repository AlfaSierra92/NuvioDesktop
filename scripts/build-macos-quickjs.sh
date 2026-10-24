#!/bin/sh
set -eu
source_dir=$1
java_home=$2
output=$3
mkdir -p "$(dirname "$output")"
cd "$source_dir"
version=$(cat quickjs/VERSION)
set -- quickjs/cutils.c quickjs/dtoa.c quickjs/libregexp.c quickjs/libunicode.c quickjs/quickjs.c common/*.c jni/*.c jni/mapping/*.c
xcrun clang -O2 -std=gnu99 -dynamiclib -fPIC -mmacosx-version-min=11.0 \
    -DCONFIG_BIGNUM "-DCONFIG_VERSION=\"$version\"" \
    -Iquickjs -Icommon -Ic-vector -Ijni -Ijni/mapping \
    "-I$java_home/include" "-I$java_home/include/darwin" \
    "$@" -Wl,-headerpad_max_install_names -Wl,-install_name,@loader_path/libquickjs.dylib -o "$output"
codesign --force --sign - "$output"
