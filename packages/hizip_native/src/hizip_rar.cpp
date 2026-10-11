// RAR is read-only. Upstream UnRAR is built in RARDLL mode; its license is
// preserved in vendor/unrar/license.txt. Never use this code for compression.
#include "hizip_rar.h"
#include <algorithm>
#include <chrono>
#include <codecvt>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <locale>
#include <map>
#include <mutex>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#else
#include <unistd.h>
#define _UNIX
#endif
#include "vendor/unrar/dll.hpp"

namespace {
// UnRAR has a process-wide ErrorHandler. Serialize whole sessions, including
// callbacks, rather than letting parallel previews corrupt error/password state.
std::mutex rar_mutex;
#ifdef _WIN32
using Utf8 = std::codecvt_utf8_utf16<wchar_t>;
#else
using Utf8 = std::codecvt_utf8<wchar_t>;
#endif
std::wstring wide(const char *s) { return std::wstring_convert<Utf8>().from_bytes(s); }
std::string utf8(const wchar_t *s) { return std::wstring_convert<Utf8>().to_bytes(s); }
std::string quoted(const std::string &s) {
  std::string result = "\"";
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') { result += '\\'; result += c; }
    else if (c < 32) { char escape[7]; std::snprintf(escape, sizeof(escape), "\\u%04x", c); result += escape; }
    else result += c;
  }
  return result + '"';
}
char *json(const std::string &s) {
  char *result = static_cast<char *>(std::malloc(s.size() + 1));
  if (result) std::memcpy(result, s.c_str(), s.size() + 1);
  return result;
}
char *error(const std::string &s) { return json("{\"error\":" + quoted(s) + "}"); }
bool safe_name(const std::string &s) {
  if (s.empty() || s[0] == '/' || s.find(':') != std::string::npos || s.find('\\') != std::string::npos) return false;
  for (size_t begin = 0; begin < s.size();) {
    size_t end = s.find('/', begin);
    std::string part = s.substr(begin, end == std::string::npos ? end : end - begin);
    if (part.empty() || part == "." || part == "..") return false;
    if (end == std::string::npos) break;
    begin = end + 1;
  }
  return true;
}
std::string status_error(int code) {
  switch (code) {
    case ERAR_MISSING_PASSWORD: return "RAR password required";
    case ERAR_BAD_PASSWORD: return "Incorrect RAR password";
    case ERAR_BAD_DATA: return "RAR data checksum failed or archive is damaged";
    case ERAR_BAD_ARCHIVE: return "Invalid or damaged RAR archive";
    case ERAR_UNKNOWN_FORMAT: return "Unsupported RAR format";
    case ERAR_NO_MEMORY: return "Not enough memory to decode RAR archive";
    case ERAR_LARGE_DICT: return "RAR dictionary exceeds the decoder memory limit";
    case ERAR_EOPEN: return "Cannot open RAR archive or a required volume";
    case ERAR_EREAD: return "Cannot read RAR archive";
    case ERAR_EREFERENCE: return "Unsupported RAR file reference";
    default: return "RAR operation failed (code " + std::to_string(code) + ")";
  }
}
struct Target { std::string output; int64_t limit; int index; bool touched = false; };
struct Context {
  Context(const char *secret, hz_rar_checkpoint check) : password(secret), checkpoint(check) {}
  const char *password;
  hz_rar_checkpoint checkpoint;
  hz_extract_progress progress = nullptr;
  hz_extract_detailed_progress detailed = nullptr;
  std::string failure;
  FILE *output = nullptr;
  bool count_data = false;
  int completed = 0, index = -1;
  int64_t bytes = 0, file_bytes = 0, file_size = 0, limit = INT64_MAX, total_limit = INT64_MAX;
  bool check() {
    if (checkpoint && !checkpoint()) { failure = "Operation cancelled"; return false; }
    return failure.empty();
  }
};
int CALLBACK callback(UINT message, LPARAM user, LPARAM p1, LPARAM p2) {
  Context &c = *reinterpret_cast<Context *>(user);
  try {
    if (!c.check()) return -1;
    switch (message) {
      case UCM_NEEDPASSWORDW: {
        if (!*c.password) { c.failure = "RAR password required"; return -1; }
        const std::wstring secret = wide(c.password);
        if (p2 <= 0 || secret.size() >= static_cast<size_t>(p2)) { c.failure = "RAR password is too long"; return -1; }
        std::copy(secret.begin(), secret.end(), reinterpret_cast<wchar_t *>(p1));
        reinterpret_cast<wchar_t *>(p1)[secret.size()] = 0;
        return 1;
      }
      case UCM_NEEDPASSWORD:
        // The wide callback above handles Unicode without platform codepages.
        c.failure = "RAR password required";
        return -1;
      case UCM_CHANGEVOLUMEW:
      case UCM_CHANGEVOLUME:
        if (p2 == RAR_VOL_ASK) {
          c.failure = "Missing RAR volume: " + (message == UCM_CHANGEVOLUMEW ? utf8(reinterpret_cast<wchar_t *>(p1)) : std::string(reinterpret_cast<char *>(p1)));
          return -1; // Never retry or prompt from the native worker.
        }
        return 1;
      case UCM_LARGEDICT: return 0; // Retain UnRAR's default resource limit.
      case UCM_PROCESSDATA: {
        if (!c.count_data) return 1;
        if (p2 < 0 || p2 > c.limit - c.file_bytes || p2 > c.total_limit - c.bytes) {
          c.failure = "Extraction size limit exceeded"; return -1;
        }
        if (c.output && std::fwrite(reinterpret_cast<void *>(p1), 1, static_cast<size_t>(p2), c.output) != static_cast<size_t>(p2)) {
          c.failure = "Disk write failed"; return -1;
        }
        c.bytes += p2; c.file_bytes += p2;
        if (c.detailed) c.detailed(c.completed, c.bytes, c.index, c.file_bytes, c.file_size);
        return 1;
      }
      default: return 1;
    }
  } catch (...) { c.failure = "Invalid Unicode in RAR archive"; return -1; }
}
struct Session {
  std::unique_lock<std::mutex> lock;
  HANDLE handle = nullptr;
  unsigned int flags = 0;
  Session(const char *path, bool listing, Context &c) : lock(rar_mutex, std::defer_lock) {
    while (!lock.try_lock()) {
      if (!c.check()) return;
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    if (!c.check()) return;
    auto filename = wide(path);
    RAROpenArchiveDataEx options{};
    options.ArcNameW = &filename[0];
    options.OpenMode = listing ? RAR_OM_LIST : RAR_OM_EXTRACT;
    options.Callback = callback;
    options.UserData = reinterpret_cast<LPARAM>(&c);
    handle = RAROpenArchiveEx(&options);
    flags = options.Flags;
    if (!handle && c.failure.empty()) c.failure = status_error(options.OpenResult);
    if (handle && (flags & ROADF_VOLUME) && !(flags & ROADF_FIRSTVOLUME)) {
      c.failure = "First RAR volume is required";
    }
  }
  ~Session() { if (handle) RARCloseArchive(handle); }
};
struct Header {
  RARHeaderDataEx data{};
  wchar_t filename[4098]{}, link[4098]{};
  Header() {
    data.FileNameEx = filename; data.FileNameExSize = 4098;
    data.RedirName = link; data.RedirNameSize = 4098;
  }
  std::string name() const {
    auto s = utf8(filename);
    std::replace(s.begin(), s.end(), '\\', '/');
    if (s.empty() || s.size() > 4096) throw std::runtime_error("Invalid or excessively long RAR entry path");
    return s;
  }
  int64_t size() const {
    uint64_t n = (static_cast<uint64_t>(data.UnpSizeHigh) << 32) | data.UnpSize;
    if (n > INT64_MAX) throw std::runtime_error("RAR file size overflow");
    return static_cast<int64_t>(n);
  }
  bool directory() const { return (data.Flags & RHDF_DIRECTORY) != 0; }
  bool regular() const {
    // RAR_TEST returns redirection metadata rather than the referenced file's
    // bytes. Do not publish empty files for symlinks, hardlinks or file copies.
    unsigned int type = data.FileAttr & 0170000;
    return !directory() && data.RedirType == 0 && (data.HostOS != 3 || type == 0 || type == 0100000);
  }
  int64_t modified() const {
    uint64_t ticks = (static_cast<uint64_t>(data.MtimeHigh) << 32) | data.MtimeLow;
    return ticks >= 116444736000000000ULL ? static_cast<int64_t>((ticks - 116444736000000000ULL) / 10000000) : 0;
  }
};
bool process(Session &session, Context &c, int operation) {
  if (!c.check()) return false;
  int code = RARProcessFile(session.handle, operation, nullptr, nullptr);
  if (code && c.failure.empty()) c.failure = status_error(code);
  return c.failure.empty();
}
FILE *create_output(const std::string &path) {
#ifdef _WIN32
  int fd = _wopen(wide(path.c_str()).c_str(), _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY, _S_IREAD | _S_IWRITE);
  if (fd < 0) return nullptr;
  FILE *file = _fdopen(fd, "wb");
  if (!file) _close(fd);
#else
  int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (fd < 0) return nullptr;
  FILE *file = fdopen(fd, "wb");
  if (!file) close(fd);
#endif
  return file;
}
void remove_output(const std::string &path) {
#ifdef _WIN32
  _wremove(wide(path.c_str()).c_str());
#else
  std::remove(path.c_str());
#endif
}
char *read_archive(const char *path, const char *password, hz_rar_checkpoint checkpoint,
    bool listing, bool verifying, std::map<std::string, Target> &targets,
    int64_t total_limit, hz_extract_progress progress, hz_extract_detailed_progress detailed) {
  Context c{password, checkpoint}; c.total_limit = total_limit;
  c.progress = progress; c.detailed = detailed;
  std::string entries; bool rar5 = hz_rar_probe(path) == 2; int64_t files = 0;
  try {
    Session session(path, listing, c);
    while (session.handle && c.check()) {
      Header header;
      int code = RARReadHeaderEx(session.handle, &header.data);
      if (code == ERAR_END_ARCHIVE) break;
      if (code) { if (c.failure.empty()) c.failure = status_error(code); break; }
      const auto name = header.name();
      rar5 = rar5 || header.data.UnpVer >= 50;
      if (listing) {
        if (!entries.empty()) entries += ',';
        entries += "{\"path\":" + quoted(name) + ",\"size\":" + std::to_string(header.size()) +
          ",\"modified\":" + std::to_string(header.modified()) +
          ",\"directory\":" + (header.directory() ? "true" : "false") +
          ",\"regular\":" + (header.regular() ? "true" : "false") +
          ",\"safe\":" + (safe_name(name) ? "true" : "false") +
          ",\"encrypted\":" + ((header.data.Flags & RHDF_ENCRYPTED) || (session.flags & ROADF_ENCHEADERS) ? "true" : "false");
        if (header.link[0] && (header.data.RedirType == 1 || header.data.RedirType == 2)) entries += ",\"link\":" + quoted(utf8(header.link));
        entries += '}';
        if (!process(session, c, RAR_SKIP)) break;
        continue;
      }
      auto found = targets.find(name);
      Target *target = found == targets.end() ? nullptr : &found->second;
      c.count_data = verifying || target != nullptr;
      c.file_bytes = 0; c.file_size = header.size();
      c.index = target ? target->index : -1;
      c.limit = target ? target->limit : INT64_MAX;
      if (target) {
        if (target->touched) { c.failure = "Duplicate RAR archive entry"; break; }
        if (!safe_name(name) || !header.regular()) { c.failure = "Links and special files cannot be extracted"; break; }
        if (header.size() > c.limit || header.size() > c.total_limit - c.bytes) { c.failure = "File exceeds extraction size limit"; break; }
        c.output = create_output(target->output);
        if (!c.output) { c.failure = "Cannot create destination file; it may already exist"; break; }
        target->touched = true;
        if (detailed) detailed(c.completed, c.bytes, target->index, 0, c.file_size);
      }
      // Testing streams through our callback without allowing UnRAR to write
      // archive paths or links to disk. Prior solid entries must be decoded too.
      int operation = c.count_data || ((session.flags & ROADF_SOLID) && header.regular()) ? RAR_TEST : RAR_SKIP;
      bool success = process(session, c, operation);
      if (c.output) {
        if (std::fclose(c.output) && c.failure.empty()) c.failure = "Cannot flush extracted file";
        c.output = nullptr;
      }
      if (!success || !c.failure.empty()) break;
      if (verifying) ++files;
      if (target) {
        if (c.file_bytes != header.size()) { c.failure = "RAR extracted size does not match its header"; break; }
        ++c.completed;
        if (progress) progress(c.completed, c.bytes);
        if (detailed) detailed(c.completed, c.bytes, target->index, c.file_bytes, c.file_size);
      }
      // Continue scanning to detect duplicate entries, missing volumes and
      // damaged later headers before publishing selected output files.
    }
    if (c.failure.empty() && !listing && !verifying && c.completed != static_cast<int>(targets.size())) c.failure = "Entry not found";
    if (c.failure.empty() && !c.check()) c.failure = "Operation cancelled";
    if (c.failure.empty()) {
      if (listing) return json("{\"entries\":[" + entries + "],\"format\":" + quoted(rar5 ? "RAR 5" : "RAR 4") + ",\"writable\":false}");
      if (verifying) return json("{\"ok\":true,\"files\":" + std::to_string(files) + ",\"bytes\":" + std::to_string(c.bytes) + "}");
      return json("{\"ok\":true}");
    }
  } catch (const std::exception &e) { c.failure = e.what(); }
  catch (...) { c.failure = "RAR operation failed"; }
  if (c.output) std::fclose(c.output);
  for (const auto &item : targets) if (item.second.touched) remove_output(item.second.output);
  return error(c.failure);
}
} // namespace

extern "C" int hz_rar_probe(const char *path) {
  try {
#ifdef _WIN32
    FILE *f = _wfopen(wide(path).c_str(), L"rb");
#else
    FILE *f = std::fopen(path, "rb");
#endif
    if (!f) return 0;
    unsigned char signature[8]{};
    size_t n = std::fread(signature, 1, sizeof(signature), f); std::fclose(f);
    if (n < 7 || std::memcmp(signature, "Rar!\x1a\x07", 6)) return 0;
    if (signature[6] == 0) return 1;
    return n == 8 && signature[6] == 1 && signature[7] == 0 ? 2 : 0;
  } catch (...) { return 0; }
}
extern "C" char *hz_rar_list(const char *path, const char *password, hz_rar_checkpoint checkpoint) {
  std::map<std::string, Target> targets;
  return read_archive(path, password, checkpoint, true, false, targets, INT64_MAX, nullptr, nullptr);
}
extern "C" char *hz_rar_verify(const char *path, const char *password, hz_rar_checkpoint checkpoint) {
  std::map<std::string, Target> targets;
  return read_archive(path, password, checkpoint, false, true, targets, INT64_MAX, nullptr, nullptr);
}
extern "C" char *hz_rar_extract(const char *path, const char *password, const char **names,
    const char **outputs, const int64_t *limits, int count, int64_t total_limit,
    hz_rar_checkpoint checkpoint, hz_extract_progress progress, hz_extract_detailed_progress detailed) {
  try {
    if (count < 0 || total_limit < 0) return error("Invalid extraction batch");
    std::map<std::string, Target> targets;
    for (int i = 0; i < count; ++i) {
      if (!names || !outputs || !limits || !names[i] || !outputs[i] || !safe_name(names[i]) || limits[i] < 0) return error("Unsafe archive path or invalid size limit");
      Target target; target.output = outputs[i]; target.limit = limits[i]; target.index = i;
      if (!targets.emplace(names[i], target).second) return error("Duplicate extraction target");
    }
    if (!count) return json("{\"ok\":true}");
    return read_archive(path, password, checkpoint, false, false, targets, total_limit, progress, detailed);
  } catch (const std::exception &e) { return error(e.what()); }
  catch (...) { return error("RAR operation failed"); }
}
