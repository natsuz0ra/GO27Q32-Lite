#include "desktop_bridge.h"
#include "resource.h"
#include <commdlg.h>
#include <shellapi.h>
#include <string>

namespace {
constexpr UINT kTray = WM_APP + 42;
constexpr UINT_PTR kTrayClickTimer = 0x474F3237;
constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunName[] = L"GO27Q32LiteFlutter";
using Value = flutter::EncodableValue;
std::string Utf8(const wchar_t* text) {
  int n = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  std::string result(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, result.data(), n, nullptr, nullptr);
  result.resize(n > 0 ? n - 1 : 0); return result;
}
}
DesktopBridge::DesktopBridge(HWND hwnd, flutter::BinaryMessenger* messenger) : hwnd_(hwnd) {
  taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
  icon_.cbSize = sizeof(icon_); icon_.hWnd = hwnd_; icon_.uID = 1;
  icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; icon_.uCallbackMessage = kTray;
  icon_.hIcon = static_cast<HICON>(LoadImageW(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_SHARED));
  wcscpy_s(icon_.szTip, L"GO27Q32 Lite · 显示器控制中心");
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(messenger, "go27q32/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "openRelease") {
      const auto* url = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      const std::string base = "https://github.com/natsuz0ra/GO27Q32-Lite/releases";
      if (!url || (*url != base && url->rfind(base + "/tag/", 0) != 0) ||
          url->find_first_of("\r\n\t\\ \"<>") != std::string::npos) {
        result->Error("url", "Invalid release URL"); return;
      }
      const std::wstring wide(url->begin(), url->end());
      const auto code = reinterpret_cast<INT_PTR>(ShellExecuteW(hwnd_, L"open", wide.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
      if (code <= 32) result->Error("browser", "Unable to open release page"); else result->Success();
      return;
    }
    if (method == "setLanguage") {
      const auto* language = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      english_ = language && *language == "en";
      wcscpy_s(icon_.szTip, english_ ? L"GO27Q32 Lite · Monitor Control Center" : L"GO27Q32 Lite · 显示器控制中心");
      if (installed_) Shell_NotifyIconW(NIM_MODIFY, &icon_);
      result->Success(); return;
    }
    if (method == "initTray") { result->Success(Value(AddTray())); return; }
    if (method == "testTrayClick" && wcsstr(GetCommandLineW(), L"--self-check")) {
      const auto* mode = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      if (mode && (*mode == "single" || *mode == "double")) {
        Handle(kTray, 0, WM_LBUTTONDOWN); Handle(kTray, 0, WM_LBUTTONUP);
        if (*mode == "double") { Handle(kTray, 0, WM_LBUTTONDBLCLK); Handle(kTray, 0, WM_LBUTTONUP); }
        result->Success(Value(static_cast<int>(GetDoubleClickTime()))); return;
      }
    }
    if (method == "trayClickCount" && wcsstr(GetCommandLineW(), L"--self-check")) { result->Success(Value(single_click_events_)); return; }
    if (method == "startupGet") {
      wchar_t buffer[32768]{}; DWORD size = sizeof(buffer);
      auto code = RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunName, RRF_RT_REG_SZ, nullptr, buffer, &size);
      result->Success(Value(code == ERROR_SUCCESS && buffer[0] != 0)); return;
    }
    if (method == "startupSet") {
      HKEY key; LSTATUS code = RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr);
      if (code == ERROR_SUCCESS) {
        if (call.arguments() && std::get<bool>(*call.arguments())) {
          wchar_t path[32768]{}; GetModuleFileNameW(nullptr, path, 32768);
          std::wstring command = L"\"" + std::wstring(path) + L"\" --tray";
          code = RegSetValueExW(key, kRunName, 0, REG_SZ, reinterpret_cast<const BYTE*>(command.c_str()), static_cast<DWORD>((command.size()+1)*sizeof(wchar_t)));
        } else { code = RegDeleteValueW(key, kRunName); if (code == ERROR_FILE_NOT_FOUND) code = ERROR_SUCCESS; }
        RegCloseKey(key);
      }
      if (code != ERROR_SUCCESS) result->Error("registry", english_ ? "Unable to update startup for the current user" : "无法更新当前用户的开机启动项"); else result->Success();
      return;
    }
    if (method == "pickExecutable" || method == "openJson" || method == "saveJson" || method == "saveReport") {
      wchar_t path[32768]{};
      bool save = method == "saveJson" || method == "saveReport";
      bool report = method == "saveReport";
      if (save) wcscpy_s(path, english_ ? (report ? L"GO27Q32-diagnostics.txt" : L"GO27Q32-profiles.json") : (report ? L"GO27Q32-诊断.txt" : L"GO27Q32-配置.json"));
      OPENFILENAMEW dialog{}; dialog.lStructSize = sizeof(dialog); dialog.hwndOwner = hwnd_;
      dialog.lpstrFile = path; dialog.nMaxFile = 32768;
      dialog.lpstrFilter = english_
        ? (method == "pickExecutable" ? L"Applications (*.exe)\0*.exe\0\0" : report ? L"Text files (*.txt)\0*.txt\0\0" : L"Profile files (*.json)\0*.json\0\0")
        : (method == "pickExecutable" ? L"应用程序 (*.exe)\0*.exe\0\0" : report ? L"文本文件 (*.txt)\0*.txt\0\0" : L"配置文件 (*.json)\0*.json\0\0");
      dialog.lpstrDefExt = report ? L"txt" : L"json";
      dialog.Flags = OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
      BOOL ok = save ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog);
      if (ok) result->Success(Value(Utf8(path)));
      else if (CommDlgExtendedError()) result->Error("dialog", english_ ? "Unable to open file dialog" : "文件对话框打开失败");
      else result->Success();
      return;
    }
    result->NotImplemented();
  });
}
DesktopBridge::~DesktopBridge() { KillTimer(hwnd_, kTrayClickTimer); if (installed_) Shell_NotifyIconW(NIM_DELETE, &icon_); }
bool DesktopBridge::AddTray() {
  if (installed_) return true;
  installed_ = Shell_NotifyIconW(NIM_ADD, &icon_) != FALSE;
  return installed_;
}
void DesktopBridge::Emit(const char* event) { channel_->InvokeMethod(event, nullptr); }
bool DesktopBridge::Handle(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_TIMER && wparam == kTrayClickTimer) {
    KillTimer(hwnd_, kTrayClickTimer);
    if (single_click_pending_) { single_click_pending_ = false; ++single_click_events_; Emit("trayLeftClick"); }
    return true;
  }
  if (message == WM_APP + 43) { KillTimer(hwnd_, kTrayClickTimer); single_click_pending_ = false; Emit("showWindow"); return true; }
  if (message == taskbar_created_) { installed_ = false; AddTray(); return false; }
  if (message != kTray) return false;
  if (lparam == WM_LBUTTONDOWN) left_down_time_ = static_cast<DWORD>(GetMessageTime());
  if (lparam == WM_LBUTTONDBLCLK) {
    KillTimer(hwnd_, kTrayClickTimer); single_click_pending_ = false;
    ignore_next_left_up_ = true; Emit("showWindow");
  }
  if (lparam == WM_LBUTTONUP) {
    if (ignore_next_left_up_) ignore_next_left_up_ = false;
    else {
      // Windows measures double clicks from the first down event. Only wait
      // the remaining classification interval, not an extra full interval.
      DWORD held = static_cast<DWORD>(GetMessageTime()) - left_down_time_;
      UINT remaining = held < GetDoubleClickTime() ? GetDoubleClickTime() - held : 1;
      single_click_pending_ = true;
      SetTimer(hwnd_, kTrayClickTimer, remaining, nullptr);
    }
  }
  if (lparam == WM_RBUTTONUP) {
    KillTimer(hwnd_, kTrayClickTimer); single_click_pending_ = false;
    ignore_next_left_up_ = false;
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, 1, english_ ? L"Open Control Center" : L"打开主窗口");
    AppendMenuW(menu, MF_STRING, 2, english_ ? L"Pause Automatic Switching" : L"暂停自动切换");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, 3, english_ ? L"Quit" : L"退出");
    POINT point; GetCursorPos(&point); SetForegroundWindow(hwnd_);
    int selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, hwnd_, nullptr);
    DestroyMenu(menu); PostMessage(hwnd_, WM_NULL, 0, 0);
    if (selected == 1) Emit("showWindow");
    if (selected == 2) Emit("pauseAutomation");
    if (selected == 3) Emit("exitRequested");
  }
  return true;
}
