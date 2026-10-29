#pragma once
#include <windows.h>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>

class DesktopBridge {
 public:
  DesktopBridge(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~DesktopBridge();
  bool Handle(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  HWND hwnd_;
  NOTIFYICONDATAW icon_{};
  bool installed_ = false;
  bool english_ = false;
  bool ignore_next_left_up_ = false;
  bool single_click_pending_ = false;
  DWORD left_down_time_ = 0;
  int single_click_events_ = 0;
  UINT taskbar_created_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  void Emit(const char* event);
  bool AddTray();
};
