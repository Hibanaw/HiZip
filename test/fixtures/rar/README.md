# RAR regression fixtures

These are byte-for-byte uu-decoded fixtures from the pinned libarchive 3.8.9
source archive in `packages/hizip_native/third_party/`. Original paths are
`libarchive/test/<filename>.uu`. Upstream license: [COPYING](https://github.com/libarchive/libarchive/blob/v3.8.9/COPYING),
also preserved as `packages/hizip_native/src/vendor/LIBARCHIVE-LICENSE`.

The encrypted fixtures use the password `password`. They contain a.txt through
d.txt with the content `This is from <filename>` (no trailing newline).

Tests copy volume fixtures before renaming or deleting parts. RAR4 volumes are
also tested with old-style .rar/.r00/.r01 names; RAR5 fixtures cover native
multivolume and solid streams. No RAR compressor or external UnRAR executable
is required to run these tests.
