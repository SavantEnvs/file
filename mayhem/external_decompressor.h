#ifndef EXTERNAL_DECOMPRESSOR_H_
#define EXTERNAL_DECOMPRESSOR_H_

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// libmagic (src/compress.c) runs a decompressor with no in-process implementation as a child
// process and fork()s a helper that calls exit(). Under libFuzzer that exit() fires the engine's
// exit hook inside the helper, which reports a bogus "fuzz target exited" crash. Reject inputs whose
// leading bytes select such a method (compress, frozen, SCO LZH, pack, zip, lzip, lrzip); the
// zlib/gzip/bzip2/xz/lz4/zstd/lzma methods are decompressed in-process and stay reachable.
static inline int needs_external_decompressor(const uint8_t* data, size_t size) {
    static const struct { const char* magic; size_t len; } ext[] = {
        {"\037\235", 2}, {"\037\236", 2}, {"\037\240", 2}, {"\037\036", 2},
        {"PK\3\4", 4}, {"LZIP", 4}, {"LRZI", 4},
    };
    for (size_t i = 0; i < sizeof(ext) / sizeof(ext[0]); i++)
        if (size >= ext[i].len && memcmp(data, ext[i].magic, ext[i].len) == 0)
            return 1;
    return 0;
}

#endif  // EXTERNAL_DECOMPRESSOR_H_
