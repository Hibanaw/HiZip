# libarchive upstream source

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
Encrypted archives, RAR/XAR writing and split-volume archives are outside v0.1.
