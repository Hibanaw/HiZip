#include "compress_request.h"

#include <shellapi.h>

#include <algorithm>
#include <utility>

#include "utils.h"

namespace {

constexpr wchar_t kFlag[] = L"--hizip-compress=";
constexpr wchar_t kMutexName[] = L"Local\\HiZipCompressCollector";
constexpr wchar_t kCollectorClass[] = L"HiZipCompressCollector";
constexpr wchar_t kMainClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kMainTitle[] = L"hizip";
constexpr ULONG_PTR kCopyDataId = 0x485A4350;  // "HZCP"
constexpr UINT_PTR kIdleTimer = 1;
constexpr UINT kIdleMilliseconds = 400;

std::optional<CompressRequest> g_pending;

// Reads the flag and the item paths from this process' command line.
std::optional<CompressRequest> ParseCommandLine() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) return std::nullopt;
  CompressRequest request;
  const size_t flag_length = wcslen(kFlag);
  for (int i = 1; i < argc; i++) {
    const std::wstring argument = argv[i];
    if (argument.rfind(kFlag, 0) == 0) {
      request.action = Utf8FromUtf16(argument.substr(flag_length).c_str());
    } else if (!argument.empty() && argument[0] != L'-') {
      request.paths.push_back(Utf8FromUtf16(argument.c_str()));
    }
  }
  ::LocalFree(argv);
  if ((request.action != "create" && request.action != "quickZip") ||
      request.paths.empty()) {
    return std::nullopt;
  }
  return request;
}

std::string Encode(const CompressRequest& request) {
  std::string text = request.action;
  for (const auto& path : request.paths) text += "\n" + path;
  return text;
}

bool SendRequest(HWND target, const CompressRequest& request) {
  const std::string text = Encode(request);
  COPYDATASTRUCT data = {};
  data.dwData = kCopyDataId;
  data.cbData = static_cast<DWORD>(text.size());
  data.lpData = const_cast<char*>(text.data());
  DWORD_PTR result = 0;
  return ::SendMessageTimeoutW(target, WM_COPYDATA, 0,
                               reinterpret_cast<LPARAM>(&data),
                               SMTO_ABORTIFHUNG, 5000, &result) != 0;
}

LRESULT CALLBACK CollectorProc(HWND window, UINT message, WPARAM wparam,
                               LPARAM lparam) {
  auto* request = reinterpret_cast<CompressRequest*>(
      ::GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_COPYDATA && request) {
    CompressRequest received;
    if (ParseCompressCopyData(reinterpret_cast<COPYDATASTRUCT*>(lparam),
                              &received) &&
        received.action == request->action) {
      request->paths.insert(request->paths.end(), received.paths.begin(),
                            received.paths.end());
    }
    ::SetTimer(window, kIdleTimer, kIdleMilliseconds, nullptr);
    return TRUE;
  }
  if (message == WM_TIMER) {
    ::PostQuitMessage(0);
    return 0;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

// Waits until no sibling process has reported an item for a short while.
void Collect(CompressRequest* request) {
  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = CollectorProc;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.lpszClassName = kCollectorClass;
  ::RegisterClassW(&window_class);
  HWND window = ::CreateWindowExW(0, kCollectorClass, L"", 0, 0, 0, 0, 0,
                                  HWND_MESSAGE, nullptr,
                                  window_class.hInstance, nullptr);
  if (!window) return;
  ::SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(request));
  ::SetTimer(window, kIdleTimer, kIdleMilliseconds, nullptr);
  MSG message;
  while (::GetMessageW(&message, nullptr, 0, 0) > 0) {
    ::TranslateMessage(&message);
    ::DispatchMessageW(&message);
  }
  ::DestroyWindow(window);
  ::UnregisterClassW(kCollectorClass, window_class.hInstance);
}

void Deduplicate(std::vector<std::string>* paths) {
  std::vector<std::string> unique;
  for (const auto& path : *paths) {
    if (std::find(unique.begin(), unique.end(), path) == unique.end()) {
      unique.push_back(path);
    }
  }
  *paths = std::move(unique);
}

}  // namespace

bool ParseCompressCopyData(const COPYDATASTRUCT* data, CompressRequest* out) {
  if (!data || data->dwData != kCopyDataId || !data->lpData ||
      data->cbData == 0) {
    return false;
  }
  const std::string text(static_cast<const char*>(data->lpData), data->cbData);
  CompressRequest request;
  size_t start = 0;
  bool first = true;
  while (start <= text.size()) {
    size_t end = text.find('\n', start);
    if (end == std::string::npos) end = text.size();
    const std::string line = text.substr(start, end - start);
    if (first) {
      request.action = line;
      first = false;
    } else if (!line.empty()) {
      request.paths.push_back(line);
    }
    start = end + 1;
  }
  if ((request.action != "create" && request.action != "quickZip") ||
      request.paths.empty()) {
    return false;
  }
  Deduplicate(&request.paths);
  *out = std::move(request);
  return true;
}

bool ForwardCompressLaunch() {
  auto request = ParseCommandLine();
  if (!request) return false;

  // The first process to take the mutex collects; the others report to it.
  for (int attempt = 0; attempt < 10; attempt++) {
    HANDLE mutex = ::CreateMutexW(nullptr, FALSE, kMutexName);
    if (mutex && ::GetLastError() != ERROR_ALREADY_EXISTS) {
      Collect(&*request);
      ::CloseHandle(mutex);
      Deduplicate(&request->paths);
      HWND main_window = ::FindWindowW(kMainClass, kMainTitle);
      if (main_window) {
        ::AllowSetForegroundWindow(ASFW_ANY);
        if (SendRequest(main_window, *request)) return true;
      }
      g_pending = std::move(request);
      return false;
    }
    if (mutex) ::CloseHandle(mutex);
    for (int wait = 0; wait < 100; wait++) {
      HWND collector =
          ::FindWindowExW(HWND_MESSAGE, nullptr, kCollectorClass, nullptr);
      if (collector) {
        if (SendRequest(collector, *request)) return true;
        break;
      }
      ::Sleep(20);
    }
  }
  g_pending = std::move(request);
  return false;
}

std::optional<CompressRequest> TakePendingCompressRequest() {
  auto request = std::move(g_pending);
  g_pending.reset();
  return request;
}
