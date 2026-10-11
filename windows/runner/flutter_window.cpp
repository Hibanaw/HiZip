#include "flutter_window.h"

#include <optional>
#include <map>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {
HWND main_archive_window = nullptr;
struct DialogHost {
  WNDPROC previous = nullptr;
  std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  bool active = false;
};
std::map<HWND, DialogHost> modal_hosts;
int modal_depth = 0;
LRESULT CALLBACK DialogWindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  const auto found = modal_hosts.find(window);
  if (found == modal_hosts.end()) return DefWindowProc(window, message, wparam, lparam);
  if (message == WM_CLOSE) {
    found->second.channel->InvokeMethod("closeRequested", nullptr);
    return 0;
  }
  const auto previous = found->second.previous;
  if (message == WM_NCDESTROY) {
    if (found->second.active) --modal_depth;
    EnableWindow(main_archive_window, modal_depth == 0);
    modal_hosts.erase(found);
  }
  return CallWindowProc(previous, window, message, wparam, lparam);
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  main_archive_window = GetHandle();
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller = reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(view_controller->engine());
    auto channel = std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
      view_controller->engine()->messenger(), "dev.hizip/task-window-host", &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([view_controller, channel](const auto& call, auto result) {
      const HWND host = GetAncestor(view_controller->view()->GetNativeWindow(), GA_ROOT);
      if (call.method_name() == "nativePointer") {
        result->Success(flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(host))));
      } else if (call.method_name() == "beginModal") {
        if (modal_hosts.find(host) == modal_hosts.end()) {
          auto previous = reinterpret_cast<WNDPROC>(SetWindowLongPtr(host, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(DialogWindowProc)));
          modal_hosts.emplace(host, DialogHost{previous, channel, false});
        }
        if (!modal_hosts[host].active) ++modal_depth;
        modal_hosts[host].active = true;
        SetWindowLongPtr(host, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(main_archive_window));
        EnableWindow(main_archive_window, FALSE);
        SetForegroundWindow(host);
        result->Success();
      } else if (call.method_name() == "endModal") {
        const auto found = modal_hosts.find(host);
        if (found != modal_hosts.end() && found->second.active) {
          found->second.active = false;
          --modal_depth;
        }
        EnableWindow(main_archive_window, modal_depth == 0);
        if (modal_depth == 0) SetForegroundWindow(main_archive_window);
        result->Success();
      } else { result->NotImplemented(); }
    });
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
