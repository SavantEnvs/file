#!/usr/bin/env bash
# Builds libmagic + `file` twice (out-of-tree, in gitignored bld-*/ dirs): a sanitized tree for the
# fuzz harnesses and a normal-flags tree for the upstream functional tests that mayhem/test.sh runs.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export CC CXX

cd "$SRC"
BIN="$SRC/bld-bin"
mkdir -p "$BIN"

# Upstream ships no ./configure; generate it (all generated files are gitignored upstream).
[ -x ./configure ] || autoreconf -i

# 1) Normal-flags tree: the functional oracle (upstream's tests/ runner + compiled magic database).
mkdir -p bld-test
(cd bld-test \
  && env -u CFLAGS -u LDFLAGS ../configure CFLAGS="-g -O2 $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
  && make -j"$MAYHEM_JOBS" \
  && make -C tests test)

# 2) Sanitized static tree: libmagic.a for the harnesses. libFuzzer coverage instrumentation
#    (-fsanitize=fuzzer-no-link) goes into the library itself, or the harnesses see only their own edges.
COV_FLAGS=""; [ -z "$LIB_FUZZING_ENGINE" ] || COV_FLAGS="-fsanitize=fuzzer-no-link"
mkdir -p bld-fuzz
(cd bld-fuzz \
  && env -u CFLAGS -u LDFLAGS ../configure --disable-shared --enable-static \
       CFLAGS="$SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS -O1" LDFLAGS="$SANITIZER_FLAGS $COV_FLAGS" \
  && make -j"$MAYHEM_JOBS")
cp bld-fuzz/magic/magic.mgc "$BIN/magic.mgc"

LIBMAGIC="$SRC/bld-fuzz/src/.libs/libmagic.a"
DEPLIBS="-lz -llz4 -lbz2 -llzma -lzstd"
CXXF="$SANITIZER_FLAGS $DEBUG_FLAGS -O1 -std=c++11 -I$SRC/bld-fuzz/src -I$SRC/src -I$SRC/mayhem"

# DWARF-3 standalone driver (C object so the harness's extern "C" reference matches)
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$SRC/bld-fuzz/standalone_main.o"
# LeakSanitizer off at build time (leaks are not the bug class we fuzz for)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$SRC/bld-fuzz/lsan_off.o"

for t in magic_fuzzer magic_fuzzer_fd magic_fuzzer_loaddb; do
  $CXX $CXXF $LIB_FUZZING_ENGINE "$SRC/mayhem/$t.cc" "$SRC/bld-fuzz/lsan_off.o" \
       "$LIBMAGIC" $DEPLIBS -o "$BIN/$t"
  $CXX $CXXF "$SRC/mayhem/$t.cc" "$SRC/bld-fuzz/standalone_main.o" "$SRC/bld-fuzz/lsan_off.o" \
       "$LIBMAGIC" $DEPLIBS -o "$BIN/$t-standalone"
done
