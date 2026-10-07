# hizip_native

Shared C archive engine for HiZip. Compression is handled by libarchive;
Dart provides UTF-8 FFI ownership and off-UI-isolate execution.

`NativeArchive.list`, `extract`, `replace`, `update`, and `create` expose the engine.
Every C result is owned JSON and must be released with `hz_free`.
Outputs must be fresh files. Rewriting never changes the source archive.
Only unencrypted ZIP is writable in v0.1.
`update` streams retained entries and appends a batch of files/directories into a
fresh ZIP, omitting explicitly moved source entries. Flutter verifies input and
archive snapshots before the coordinated commit; failed batches leave the source intact.

macOS also registers `dev.hizip/native_files` for system file/application icons,
default application lookup, available application enumeration, Quick Look, sandbox-compatible staging and coordinated
atomic replacement. The macOS host window inherits `HizipPreviewWindow` so the
system preview panel can acquire its controller through the window responder chain.
Quick Look sends navigation events back to Flutter and previews the same tracked
temporary files used for external editing.
`applicationsForFile` returns compatible applications with icons and the default
application marked. `chooseApplication` presents the system app picker; `openWith`
opens the monitored temporary file in the chosen app without changing system defaults.
The channel also starts AppKit file URL drag sessions and forwards file-manager
copy/paste/select-all shortcuts when the file workspace has focus. Apple builds
use the system libarchive;
other native builds compile the pinned upstream source archive via CMake.

See the root README for platform status, limits and test commands, and
`third_party/README.md` for provenance and licensing.
