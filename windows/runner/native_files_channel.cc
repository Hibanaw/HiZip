#include "native_files_channel.h"

// This must come before shlobj.h/shellapi.h.
#include <windows.h>

#include <commctrl.h>
#include <commdlg.h>
#include <commoncontrols.h>
#include <gdiplus.h>
#include <objbase.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "utils.h"

// Windows implementation of the dev.hizip/native_files channel's file-icon
// and open-with/default-application methods, mirroring macOS's
// HizipNativePlugin.swift (NSWorkspace/UTType) and Linux's
// my_application.cc (GTK/gio).
namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

HWND g_owner = nullptr;
bool g_gdiplus_started = false;
ULONG_PTR g_gdiplus_token = 0;

void EnsureGdiPlus() {
  if (g_gdiplus_started) return;
  Gdiplus::GdiplusStartupInput input;
  Gdiplus::GdiplusStartup(&g_gdiplus_token, &input, nullptr);
  g_gdiplus_started = true;
}

std::string ArgString(const EncodableMap* args, const char* key) {
  if (!args) return std::string();
  auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return std::string();
  if (const auto* value = std::get_if<std::string>(&it->second)) return *value;
  return std::string();
}

bool ArgBool(const EncodableMap* args, const char* key, bool fallback) {
  if (!args) return fallback;
  auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return fallback;
  if (const auto* value = std::get_if<bool>(&it->second)) return *value;
  return fallback;
}

int ArgInt(const EncodableMap* args, const char* key, int fallback) {
  if (!args) return fallback;
  auto it = args->find(EncodableValue(std::string(key)));
  if (it == args->end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

bool PngEncoderClsid(CLSID* clsid) {
  UINT count = 0, size = 0;
  Gdiplus::GetImageEncodersSize(&count, &size);
  if (size == 0) return false;
  std::vector<BYTE> buffer(size);
  auto* codecs = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(count, size, codecs);
  for (UINT i = 0; i < count; i++) {
    if (wcscmp(codecs[i].MimeType, L"image/png") == 0) {
      *clsid = codecs[i].Clsid;
      return true;
    }
  }
  return false;
}

// Renders |icon| into a square |size|x|size| PNG, or an empty vector on
// failure.
std::vector<uint8_t> IconToPng(HICON icon, int size) {
  if (!icon) return {};
  EnsureGdiPlus();
  Gdiplus::Bitmap source(icon);
  if (source.GetLastStatus() != Gdiplus::Ok) return {};
  Gdiplus::Bitmap target(size, size, PixelFormat32bppARGB);
  Gdiplus::Graphics graphics(&target);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  graphics.SetCompositingMode(Gdiplus::CompositingModeSourceCopy);
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  graphics.DrawImage(&source, 0, 0, size, size);
  CLSID png_clsid;
  if (!PngEncoderClsid(&png_clsid)) return {};
  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(nullptr, TRUE, &stream) != S_OK) return {};
  std::vector<uint8_t> bytes;
  if (target.Save(stream, &png_clsid, nullptr) == Gdiplus::Ok) {
    HGLOBAL global = nullptr;
    if (GetHGlobalFromStream(stream, &global) == S_OK) {
      const SIZE_T data_size = GlobalSize(global);
      void* data = GlobalLock(global);
      if (data && data_size > 0) {
        bytes.assign(static_cast<uint8_t*>(data),
                     static_cast<uint8_t*>(data) + data_size);
      }
      if (data) GlobalUnlock(global);
    }
  }
  stream->Release();
  return bytes;
}

// Picks the smallest system image list that can still cover |size| without
// upscaling (large tops out at 32px, extra-large at 48px, jumbo at 256px),
// mirroring how macOS's NSWorkspace icon is resolution-independent and only
// ever rendered down to the requested pixel size, never blown back up.
int SystemImageListFor(int size) {
  if (size <= 32) return SHIL_LARGE;
  if (size <= 48) return SHIL_EXTRALARGE;
  return SHIL_JUMBO;
}

// Looks up |path|'s (or, with SHGFI_USEFILEATTRIBUTES, |attributes|' only)
// shell icon index, then fetches that icon at close to |size| from the
// jumbo/extra-large system image list instead of the single small/large icon
// SHGFI_ICON returns -- the latter is fixed at ~32px/48px, so scaling it up
// to a requested size like 128 or 256 blurs it. Falls back to the regular
// SHGFI_ICON icon (and GDI+ upscaling) if the image list lookup fails.
std::vector<uint8_t> ShellIcon(const std::wstring& path, DWORD attributes,
                                UINT extra_flags, int size) {
  SHFILEINFOW info = {};
  const UINT index_flags = SHGFI_SYSICONINDEX | extra_flags;
  if (SHGetFileInfoW(path.c_str(), attributes, &info, sizeof(info),
                      index_flags)) {
    IImageList* image_list = nullptr;
    if (SUCCEEDED(SHGetImageList(SystemImageListFor(size),
                                  IID_PPV_ARGS(&image_list))) &&
        image_list) {
      HICON icon = nullptr;
      const HRESULT hr =
          image_list->GetIcon(info.iIcon, ILD_TRANSPARENT, &icon);
      image_list->Release();
      if (SUCCEEDED(hr) && icon) {
        std::vector<uint8_t> png = IconToPng(icon, size);
        DestroyIcon(icon);
        if (!png.empty()) return png;
      }
    }
  }
  SHFILEINFOW fallback = {};
  if (!SHGetFileInfoW(path.c_str(), attributes, &fallback, sizeof(fallback),
                       SHGFI_ICON | SHGFI_LARGEICON | extra_flags)) {
    return {};
  }
  std::vector<uint8_t> png = IconToPng(fallback.hIcon, size);
  DestroyIcon(fallback.hIcon);
  return png;
}

// The icon for a file named |name| (which need not exist on disk, as only
// its extension is inspected) or for a folder when |directory| is true,
// scaled to |size|.
std::vector<uint8_t> ExtensionIcon(const std::wstring& name, bool directory,
                                   int size) {
  const DWORD attributes =
      directory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
  const std::wstring probe = directory ? L"folder" : name;
  return ShellIcon(probe, attributes, SHGFI_USEFILEATTRIBUTES, size);
}

// The icon embedded in an installed application's executable, scaled to
// |size|.
std::vector<uint8_t> ExecutableIcon(const std::wstring& exe_path, int size) {
  return ShellIcon(exe_path, 0, 0, size);
}

// The display name from an executable's version resource, or its file name
// without extension when it has none.
std::wstring ExecutableDisplayName(const std::wstring& exe_path) {
  DWORD handle = 0;
  const DWORD size = GetFileVersionInfoSizeW(exe_path.c_str(), &handle);
  if (size > 0) {
    std::vector<BYTE> data(size);
    if (GetFileVersionInfoW(exe_path.c_str(), 0, size, data.data())) {
      struct LangCodepage {
        WORD language, codepage;
      }* translations = nullptr;
      UINT translation_bytes = 0;
      if (VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                        reinterpret_cast<LPVOID*>(&translations),
                        &translation_bytes) &&
          translation_bytes >= sizeof(LangCodepage)) {
        wchar_t block[64];
        swprintf_s(block, L"\\StringFileInfo\\%04x%04x\\FileDescription",
                  translations[0].language, translations[0].codepage);
        LPVOID value = nullptr;
        UINT value_bytes = 0;
        if (VerQueryValueW(data.data(), block, &value, &value_bytes) &&
            value_bytes > 0) {
          std::wstring description(static_cast<wchar_t*>(value));
          if (!description.empty()) return description;
        }
      }
    }
  }
  std::wstring filename = exe_path;
  const size_t slash = filename.find_last_of(L"\\/");
  if (slash != std::wstring::npos) filename = filename.substr(slash + 1);
  const size_t dot = filename.find_last_of(L'.');
  if (dot != std::wstring::npos) filename = filename.substr(0, dot);
  return filename;
}

std::wstring ExtensionOf(const std::wstring& name) {
  const size_t dot = name.find_last_of(L'.');
  if (dot == std::wstring::npos || dot == 0) return std::wstring();
  return name.substr(dot);
}

EncodableValue ApplicationInfo(const std::wstring& exe_path, bool is_default) {
  EncodableMap info;
  info[EncodableValue("name")] =
      EncodableValue(Utf8FromUtf16(ExecutableDisplayName(exe_path).c_str()));
  info[EncodableValue("path")] =
      EncodableValue(Utf8FromUtf16(exe_path.c_str()));
  info[EncodableValue("default")] = EncodableValue(is_default);
  const std::vector<uint8_t> icon = ExecutableIcon(exe_path, 64);
  if (!icon.empty()) info[EncodableValue("icon")] = EncodableValue(icon);
  return EncodableValue(info);
}

// The default application's executable path for files with |extension|, or
// an empty string if none is registered.
std::wstring DefaultApplicationPath(const std::wstring& extension) {
  if (extension.empty()) return std::wstring();
  wchar_t exe_path[MAX_PATH] = {};
  DWORD exe_path_size = MAX_PATH;
  const HRESULT hr =
      AssocQueryStringW(ASSOCF_INIT_IGNOREUNKNOWN, ASSOCSTR_EXECUTABLE,
                        extension.c_str(), nullptr, exe_path, &exe_path_size);
  if (FAILED(hr)) return std::wstring();
  return std::wstring(exe_path);
}

// Every application registered to open |extension|, with the default (if
// any) listed first.
std::vector<std::wstring> AssociatedApplicationPaths(
    const std::wstring& extension) {
  std::vector<std::wstring> paths;
  if (extension.empty()) return paths;
  const std::wstring default_path = DefaultApplicationPath(extension);
  if (!default_path.empty()) paths.push_back(default_path);
  IEnumAssocHandlers* enumerator = nullptr;
  if (SUCCEEDED(SHAssocEnumHandlers(extension.c_str(),
                                    ASSOC_FILTER_RECOMMENDED, &enumerator)) &&
      enumerator) {
    IAssocHandler* handler = nullptr;
    ULONG fetched = 0;
    while (enumerator->Next(1, &handler, &fetched) == S_OK && fetched > 0) {
      wchar_t* command = nullptr;
      if (SUCCEEDED(handler->GetName(&command)) && command) {
        const std::wstring path(command);
        CoTaskMemFree(command);
        if (std::find(paths.begin(), paths.end(), path) == paths.end()) {
          paths.push_back(path);
        }
      }
      handler->Release();
      handler = nullptr;
    }
    enumerator->Release();
  }
  return paths;
}

std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;

void HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());

  if (method == "fileIcon") {
    const std::wstring name = Utf16FromUtf8(ArgString(args, "path"));
    const bool directory = ArgBool(args, "directory", false);
    const int size = std::clamp(ArgInt(args, "pixelSize", 64), 16, 1024);
    const std::vector<uint8_t> png = ExtensionIcon(name, directory, size);
    if (png.empty()) {
      result->Success();
    } else {
      result->Success(EncodableValue(png));
    }
    return;
  }

  if (method == "defaultApplication") {
    const std::wstring name = Utf16FromUtf8(ArgString(args, "path"));
    const std::wstring exe_path = DefaultApplicationPath(ExtensionOf(name));
    if (exe_path.empty()) {
      result->Success();
    } else {
      result->Success(ApplicationInfo(exe_path, true));
    }
    return;
  }

  if (method == "applicationsForFile") {
    const std::wstring name = Utf16FromUtf8(ArgString(args, "path"));
    const std::wstring extension = ExtensionOf(name);
    const std::wstring default_path = DefaultApplicationPath(extension);
    const auto paths = AssociatedApplicationPaths(extension);
    EncodableList items;
    for (const auto& path : paths) {
      items.push_back(
          ApplicationInfo(path, !default_path.empty() && path == default_path));
    }
    result->Success(EncodableValue(items));
    return;
  }

  if (method == "openWith") {
    const std::wstring path = Utf16FromUtf8(ArgString(args, "path"));
    const std::wstring application =
        Utf16FromUtf8(ArgString(args, "application"));
    const std::wstring quoted = L"\"" + path + L"\"";
    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_NOASYNC;
    info.hwnd = g_owner;
    info.lpFile = application.c_str();
    info.lpParameters = quoted.c_str();
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) {
      result->Error("open_application", "Cannot open application");
    } else {
      result->Success();
    }
    return;
  }

  if (method == "chooseApplication") {
    wchar_t file_name[MAX_PATH] = {};
    wchar_t program_files[MAX_PATH] = {};
    SHGetFolderPathW(nullptr, CSIDL_PROGRAM_FILES, nullptr, 0, program_files);
    OPENFILENAMEW open = {};
    open.lStructSize = sizeof(open);
    open.hwndOwner = g_owner;
    open.lpstrFilter = L"程序\0*.exe\0";
    open.lpstrFile = file_name;
    open.nMaxFile = MAX_PATH;
    open.lpstrInitialDir = program_files;
    open.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;
    if (GetOpenFileNameW(&open)) {
      result->Success(ApplicationInfo(file_name, false));
    } else {
      result->Success();
    }
    return;
  }

  result->NotImplemented();
}

}  // namespace

void RegisterNativeFilesChannel(flutter::BinaryMessenger* messenger,
                                HWND owner) {
  g_owner = owner;
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "dev.hizip/native_files",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}
