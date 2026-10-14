#ifndef RUNNER_COMPRESS_REQUEST_H_
#define RUNNER_COMPRESS_REQUEST_H_

#include <windows.h>

#include <optional>
#include <string>
#include <vector>

// Explorer context-menu requests. Explorer starts one process per selected
// item (`hizip.exe --hizip-compress=<create|quickZip> "<path>"`); these
// processes elect a collector that merges the whole selection into a single
// request, hands it to an already-running main window, or keeps it for a
// freshly started one. Mirrors macOS's hizip://compress Finder request.
struct CompressRequest {
  std::string action;              // "create" or "quickZip"
  std::vector<std::string> paths;  // UTF-8, absolute, de-duplicated
};

// Handles a context-menu launch. Returns true when the request was passed on
// and this process should exit; otherwise the request (if any) is kept for
// TakePendingCompressRequest() and startup continues normally.
bool ForwardCompressLaunch();

std::optional<CompressRequest> TakePendingCompressRequest();

// WM_COPYDATA codec used between hizip processes.
bool ParseCompressCopyData(const COPYDATASTRUCT* data, CompressRequest* out);

#endif  // RUNNER_COMPRESS_REQUEST_H_
