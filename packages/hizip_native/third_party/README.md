# Native archive dependencies

`libarchive-3.8.9.tar.xz` is the unmodified upstream release from
https://www.libarchive.org/downloads/libarchive-3.8.9.tar.xz

SHA-256: `888c934f9d95648ecb9163dc8e23ab80a476ecb81a8f1154704a227b5b676dde`

Windows, Linux and Android CMake builds compile the source archive. CMake needs
no network access for this dependency. Apple builds currently reuse the OS
libarchive library. Exported ABI headers are copied from Homebrew libarchive
3.8.8; only stable libarchive 3.x entry points are used.

Upstream licensing is preserved in the archive (`COPYING` and per-file
notices); a copy is also provided in `../src/vendor/LIBARCHIVE-LICENSE`.
Do not strip these when distributing binaries.

Available codecs depend on libraries detected by upstream CMake. Install zlib
and liblzma development packages for desktop builds. Android zlib is supplied
by the NDK; cross-compiled liblzma/bzip2/zstd can be added for more codecs.
RAR/XAR writing and PKZIP .z01 volumes are unsupported; RAR reading uses the separate UnRAR decoder below.

## UnRAR 7.23

`../src/vendor/unrar/` contains the unmodified official source archive
https://www.rarlab.com/rar/unrarsrc-7.2.7.tar.gz (upstream version 7.23).

SHA-256: `01d903a7dcf413cb2925696d7796e48e38d471f79bfe7ef3ad2aebf6c12dbefd`

All platforms compile the library units from the upstream makefile with
`RARDLL` defined. CMake uses `../src/unrar.cmake`; CocoaPods compiles the
corresponding forwarders under each platform's `Classes/Unrar/`. These forwarders
include the shared sources, not independent copies. Build time needs no network.

UnRAR is freeware source with restrictions, not an unrestricted open-source
compression library. Only decompression is used. Preserve `license.txt` and
`acknow.txt`; the full license is included in the native package LICENSE and
Apple resource bundles. Never use these sources to implement RAR compression.
