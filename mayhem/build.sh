#!/usr/bin/env bash
#
# mayhem/build.sh — build vengi's fuzz harnesses (sanitized) AND its unit-test suite (normal flags).
# Runs inside the commit image as `mayhem` in /mayhem. Re-runnable and offline: every dependency
# vengi builds (SDL3, lua, glm, brotli, ...) is vendored under contrib/libs (USE_LIBS_FORCE_LOCAL).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# <target> <file extension loadFormat() dispatches on>; one libFuzzer binary per format.
TARGETS=(
  "fuzz_vox vox"
  "fuzz_qb qb"
  "fuzz_qbt qbt"
  "fuzz_vxl vxl"
  "fuzz_gox gox"
  "fuzz_vengi vengi"
  "fuzz_kv6 kv6"
  "fuzz_gltf gltf"
)

CMAKE_COMMON=(
  -G Ninja
  -DUSE_LIBS_FORCE_LOCAL=ON -DSDL_UNIX_CONSOLE_BUILD=ON -DUSE_CCACHE=OFF
  -DUSE_LINK_TIME_OPTIMIZATION=OFF -DUSE_BENCHMARKS=OFF -DVISUALTESTS=OFF
  -DVOXEDIT=OFF -DTHUMBNAILER=OFF -DVOXCONVERT=OFF -DPALCONVERT=OFF
)

# 1) The project's unit tests with NORMAL flags (honest oracle; mayhem/test.sh only runs the result).
cmake -S . -B build-tests "${CMAKE_COMMON[@]}" -DCMAKE_BUILD_TYPE=Debug -DUNITTESTS=ON \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build build-tests --target tests-voxelformat -j"$MAYHEM_JOBS"

# 2) The libraries the harness links, instrumented: sanitizers + coverage + DWARF<=3.
#    fuzzer-no-link puts SanCov in the library (the engine alone only instruments the harness TU).
FUZZ_FLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
cmake -S . -B build-fuzz "${CMAKE_COMMON[@]}" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DUNITTESTS=OFF \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS"
cmake --build build-fuzz --target voxelformat app -j"$MAYHEM_JOBS"

# 3) The harnesses: each linked once with libFuzzer and once with the run-once standalone driver.
mapfile -t LIBS < <(find build-fuzz -path '*/lib/lib*.a' ! -name 'libgtest*' ! -name 'libtest-*' | sort)
# Compile the harness with the include paths and defines the library TUs use.
mapfile -t INCS < <(python3 "$SRC/mayhem/includes.py" build-fuzz/compile_commands.json)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o /tmp/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
for t in "${TARGETS[@]}"; do
  read -r name ext <<<"$t"
  $CXX -std=c++17 -fno-rtti -fno-exceptions $SANITIZER_FLAGS $DEBUG_FLAGS -O1 "${INCS[@]}" -DFUZZ_EXT="\"$ext\"" \
    -c "$SRC/mayhem/harness_voxelformat.cpp" -o "/tmp/$name.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "/tmp/$name.o" /tmp/lsan_off.o \
    -Wl,--start-group "${LIBS[@]}" -Wl,--end-group -lpthread -ldl -lm -o "/mayhem/$name"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "/tmp/$name.o" /tmp/lsan_off.o /tmp/standalone_main.o \
    -Wl,--start-group "${LIBS[@]}" -Wl,--end-group -lpthread -ldl -lm -o "/mayhem/$name-standalone"
done
