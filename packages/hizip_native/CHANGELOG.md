## 0.1.0

- Add streaming libarchive listing, extraction, ZIP creation and ZIP replacement.
- Add background-isolate FFI bindings and explicit native result ownership.
- Preserve UTF-8 entry names regardless of the host process locale.
- Add macOS sandbox-compatible staging and coordinated file replacement.
- Vendor the unmodified libarchive 3.8.9 source release for CMake builds.
- Reject existing extraction outputs, unsafe paths, links and oversized files.
