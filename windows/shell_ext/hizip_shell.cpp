// Windows 11 context-menu entry for HiZip: an IExplorerCommand with a
// "Create Archive…" / "Quick Create ZIP" submenu. It is registered through
// the sparse package in hizip_shell.AppxManifest.xml (see
// docs/WINDOWS_EXPLORER.md) and hosted by Explorer's COM surrogate. Invoking
// an item starts hizip.exe --hizip-compress=<action> with the selected paths;
// the app merges and handles the request (windows/runner/compress_request.cc).
#include <windows.h>

#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl_core.h>

#include <new>
#include <string>
#include <vector>

// {7A3C9E52-5B1D-4F6E-9A40-2C8D1E6F0B73}
static const CLSID kClsidHiZipCommand = {
    0x7a3c9e52, 0x5b1d, 0x4f6e, {0x9a, 0x40, 0x2c, 0x8d, 0x1e, 0x6f, 0x0b, 0x73}};

namespace {

HMODULE g_module = nullptr;
LONG g_objects = 0;

enum class Kind { kRoot, kCreate, kQuickZip };

struct Labels {
  const wchar_t* language;
  const wchar_t* create;
  const wchar_t* quick_zip;
};

// Like the Finder extension, labels follow the system language.
const Labels kLabels[] = {
    {L"zh", L"创建压缩包…", L"快速创建 ZIP"},
    {L"ja", L"アーカイブを作成…", L"ZIP をすばやく作成"},
    {L"ko", L"압축 파일 만들기…", L"ZIP 빠르게 만들기"},
    {L"fr", L"Créer une archive…", L"Créer un ZIP rapidement"},
    {L"de", L"Archiv erstellen…", L"ZIP schnell erstellen"},
    {L"es", L"Crear archivo…", L"Crear ZIP rápidamente"},
    {L"en", L"Create Archive…", L"Quick Create ZIP"},
};

const Labels& CurrentLabels() {
  wchar_t name[LOCALE_NAME_MAX_LENGTH] = {};
  if (GetUserDefaultLocaleName(name, LOCALE_NAME_MAX_LENGTH)) {
    for (const auto& labels : kLabels) {
      if (_wcsnicmp(name, labels.language, 2) == 0) return labels;
    }
  }
  return kLabels[6];
}

std::wstring ExecutablePath() {
  wchar_t path[MAX_PATH * 2] = {};
  GetModuleFileNameW(g_module, path, ARRAYSIZE(path));
  PathRemoveFileSpecW(path);
  return std::wstring(path) + L"\\hizip.exe";
}

// What to start. Executables inside a Store package cannot be started
// directly; the package declares the app execution alias "hizip.exe" instead.
std::wstring LauncherPath() {
  const std::wstring executable = ExecutablePath();
  if (StrStrIW(executable.c_str(), L"\\WindowsApps\\") == nullptr) {
    return executable;
  }
  PWSTR local_app_data = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                  &local_app_data))) {
    return executable;
  }
  std::wstring alias =
      std::wstring(local_app_data) + L"\\Microsoft\\WindowsApps\\hizip.exe";
  CoTaskMemFree(local_app_data);
  return alias;
}

// Quotes one command-line argument for CommandLineToArgvW.
std::wstring Quote(const std::wstring& argument) {
  std::wstring quoted = L"\"";
  size_t backslashes = 0;
  for (wchar_t c : argument) {
    if (c == L'\\') {
      backslashes++;
      continue;
    }
    if (c == L'"') quoted.append(backslashes * 2 + 1, L'\\');
    else quoted.append(backslashes, L'\\');
    backslashes = 0;
    quoted += c;
  }
  quoted.append(backslashes * 2, L'\\');
  return quoted + L"\"";
}

class Command;

class CommandEnumerator : public IEnumExplorerCommand {
 public:
  CommandEnumerator() { InterlockedIncrement(&g_objects); }
  ~CommandEnumerator() { InterlockedDecrement(&g_objects); }

  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    if (riid == IID_IUnknown || riid == IID_IEnumExplorerCommand) {
      *object = static_cast<IEnumExplorerCommand*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override {
    return InterlockedIncrement(&references_);
  }
  IFACEMETHODIMP_(ULONG) Release() override {
    const ULONG count = InterlockedDecrement(&references_);
    if (count == 0) delete this;
    return count;
  }
  IFACEMETHODIMP Next(ULONG count, IExplorerCommand** commands,
                      ULONG* fetched) override;
  IFACEMETHODIMP Skip(ULONG count) override {
    index_ += count;
    return index_ <= 2 ? S_OK : S_FALSE;
  }
  IFACEMETHODIMP Reset() override {
    index_ = 0;
    return S_OK;
  }
  IFACEMETHODIMP Clone(IEnumExplorerCommand** clone) override {
    auto* copy = new (std::nothrow) CommandEnumerator();
    if (!copy) return E_OUTOFMEMORY;
    copy->index_ = index_;
    *clone = copy;
    return S_OK;
  }

 private:
  LONG references_ = 1;
  ULONG index_ = 0;
};

class Command : public IExplorerCommand {
 public:
  explicit Command(Kind kind) : kind_(kind) {
    InterlockedIncrement(&g_objects);
  }
  ~Command() { InterlockedDecrement(&g_objects); }

  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    if (riid == IID_IUnknown || riid == IID_IExplorerCommand) {
      *object = static_cast<IExplorerCommand*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override {
    return InterlockedIncrement(&references_);
  }
  IFACEMETHODIMP_(ULONG) Release() override {
    const ULONG count = InterlockedDecrement(&references_);
    if (count == 0) delete this;
    return count;
  }

  IFACEMETHODIMP GetTitle(IShellItemArray*, PWSTR* name) override {
    const Labels& labels = CurrentLabels();
    switch (kind_) {
      case Kind::kRoot: return SHStrDupW(L"HiZip", name);
      case Kind::kCreate: return SHStrDupW(labels.create, name);
      default: return SHStrDupW(labels.quick_zip, name);
    }
  }
  IFACEMETHODIMP GetIcon(IShellItemArray*, PWSTR* icon) override {
    if (kind_ != Kind::kRoot) {
      *icon = nullptr;
      return E_NOTIMPL;
    }
    return SHStrDupW((ExecutablePath() + L",0").c_str(), icon);
  }
  IFACEMETHODIMP GetToolTip(IShellItemArray*, PWSTR* tip) override {
    *tip = nullptr;
    return E_NOTIMPL;
  }
  IFACEMETHODIMP GetCanonicalName(GUID* guid) override {
    *guid = GUID_NULL;
    return S_OK;
  }
  IFACEMETHODIMP GetState(IShellItemArray*, BOOL, EXPCMDSTATE* state) override {
    *state = ECS_ENABLED;
    return S_OK;
  }
  IFACEMETHODIMP GetFlags(EXPCMDFLAGS* flags) override {
    *flags = kind_ == Kind::kRoot ? ECF_HASSUBCOMMANDS : ECF_DEFAULT;
    return S_OK;
  }
  IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand** enumerator) override {
    if (kind_ != Kind::kRoot) {
      *enumerator = nullptr;
      return E_NOTIMPL;
    }
    *enumerator = new (std::nothrow) CommandEnumerator();
    return *enumerator ? S_OK : E_OUTOFMEMORY;
  }
  IFACEMETHODIMP Invoke(IShellItemArray* items, IBindCtx*) override;

 private:
  LONG references_ = 1;
  Kind kind_;
};

IFACEMETHODIMP CommandEnumerator::Next(ULONG count, IExplorerCommand** commands,
                                       ULONG* fetched) {
  ULONG produced = 0;
  while (produced < count && index_ < 2) {
    commands[produced] =
        new (std::nothrow) Command(index_ == 0 ? Kind::kCreate : Kind::kQuickZip);
    if (!commands[produced]) break;
    index_++;
    produced++;
  }
  if (fetched) *fetched = produced;
  return produced == count ? S_OK : S_FALSE;
}

IFACEMETHODIMP Command::Invoke(IShellItemArray* items, IBindCtx*) {
  if (kind_ == Kind::kRoot || !items) return S_OK;
  DWORD count = 0;
  if (FAILED(items->GetCount(&count)) || count == 0) return S_OK;

  std::wstring command_line =
      std::wstring(L"--hizip-compress=") +
      (kind_ == Kind::kCreate ? L"create" : L"quickZip");
  size_t added = 0;
  for (DWORD i = 0; i < count; i++) {
    IShellItem* item = nullptr;
    if (FAILED(items->GetItemAt(i, &item))) continue;
    PWSTR path = nullptr;
    if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
      command_line += L" " + Quote(path);
      added++;
      CoTaskMemFree(path);
    }
    item->Release();
  }
  if (added == 0) return S_OK;

  const std::wstring launcher = LauncherPath();
  SHELLEXECUTEINFOW info = {};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_FLAG_NO_UI | SEE_MASK_NOASYNC;
  info.lpFile = launcher.c_str();
  info.lpParameters = command_line.c_str();
  info.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&info)) return HRESULT_FROM_WIN32(GetLastError());
  return S_OK;
}

class Factory : public IClassFactory {
 public:
  IFACEMETHODIMP QueryInterface(REFIID riid, void** object) override {
    if (riid == IID_IUnknown || riid == IID_IClassFactory) {
      *object = static_cast<IClassFactory*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return 2; }
  IFACEMETHODIMP_(ULONG) Release() override { return 1; }
  IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID riid,
                                void** object) override {
    *object = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    auto* command = new (std::nothrow) Command(Kind::kRoot);
    if (!command) return E_OUTOFMEMORY;
    const HRESULT result = command->QueryInterface(riid, object);
    command->Release();
    return result;
  }
  IFACEMETHODIMP LockServer(BOOL lock) override {
    if (lock) InterlockedIncrement(&g_objects);
    else InterlockedDecrement(&g_objects);
    return S_OK;
  }
};

Factory g_factory;

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    DisableThreadLibraryCalls(module);
  }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void** object) {
  if (clsid != kClsidHiZipCommand) {
    *object = nullptr;
    return CLASS_E_CLASSNOTAVAILABLE;
  }
  return g_factory.QueryInterface(riid, object);
}

STDAPI DllCanUnloadNow() { return g_objects == 0 ? S_OK : S_FALSE; }
