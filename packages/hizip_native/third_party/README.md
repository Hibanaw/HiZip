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


## HarmonyOS target codecs

HarmonyOS builds also compile these unmodified official source releases, with
SHA-256 pins in `../src/ohos_codecs.cmake`:

- XZ/liblzma 5.8.4: https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.xz
  — `4ce24038fd4221e0d13bc1a2de7a4db56e90b92b3bf75321f6c14be73f65de4b`
- bzip2 1.0.8: https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
  — `ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269`
- Mbed TLS 3.6.7: https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2
  — `a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6`

The complete upstream license notices remain inside the archives. Only the
libraries are linked into HiZip; command-line tools and upstream tests are
disabled. Keep all license notices when redistributing. The liblzma library uses
the upstream 0BSD license, bzip2 its upstream license, and Mbed TLS is used under
Apache-2.0.
