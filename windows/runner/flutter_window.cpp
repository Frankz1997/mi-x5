#include "flutter_window.h"

#include <optional>
#include <cmath>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <filesystem>
#include "window_backdrop.h"

#include "flutter/generated_plugin_registrant.h"

#ifdef _DEBUG
namespace {
bool CapturePanel(HWND window) {
  RECT rect;
  if (!IsWindowVisible(window) || !GetWindowRect(window, &rect)) return false;
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0 || width > 4096 || height > 4096) return false;
  HDC screen = GetDC(nullptr);
  if (!screen) return false;
  HDC memory = CreateCompatibleDC(screen);
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  HBITMAP bitmap = CreateDIBSection(screen, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (!memory || !bitmap) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    ReleaseDC(nullptr, screen);
    return false;
  }
  HGDIOBJ previous = SelectObject(memory, bitmap);
  const bool captured = BitBlt(memory, 0, 0, width, height, screen,
                              rect.left, rect.top, SRCCOPY | CAPTUREBLT);
  bool saved = false;
  if (captured) {
    wchar_t executable[MAX_PATH];
    if (GetModuleFileNameW(nullptr, executable, MAX_PATH)) {
      const auto path = std::filesystem::path(executable).parent_path() /
                        L"mi-x5-native-review.bmp";
      HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                                CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (file != INVALID_HANDLE_VALUE) {
        BITMAPFILEHEADER header = {};
        header.bfType = 0x4d42;
        header.bfOffBits = sizeof(header) + sizeof(BITMAPINFOHEADER);
        const DWORD length = static_cast<DWORD>(width * height * 4);
        header.bfSize = header.bfOffBits + length;
        DWORD written;
        saved = WriteFile(file, &header, sizeof(header), &written, nullptr) &&
                WriteFile(file, &info.bmiHeader, sizeof(BITMAPINFOHEADER), &written, nullptr) &&
                WriteFile(file, pixels, length, &written, nullptr);
        CloseHandle(file);
      }
    }
  }
  SelectObject(memory, previous);
  DeleteObject(bitmap);
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return saved;
}
}  // namespace
#endif

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  backdrop_ = std::make_unique<WindowBackdrop>();

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "mi_x5/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
#ifdef _DEBUG
        if (call.method_name() == "capturePanelReview") {
          result->Success(flutter::EncodableValue(CapturePanel(GetHandle())));
          return;
        }
#endif
        if (call.method_name() != "setBlur") {
          result->NotImplemented();
          return;
        }
        const auto* coordinates = call.arguments()
            ? std::get_if<flutter::EncodableList>(call.arguments()) : nullptr;
        if (!coordinates || coordinates->size() < 6 ||
            coordinates->size() > 10000 || coordinates->size() % 2 != 0) {
          result->Error("invalid_shape", "Invalid panel outline.");
          return;
        }
        const double scale = GetDpiForWindow(GetHandle()) / 96.0;
        std::vector<D2D1_POINT_2F> points;
        for (size_t i = 0; i < coordinates->size(); i += 2) {
          const auto* x = std::get_if<double>(&(*coordinates)[i]);
          const auto* y = std::get_if<double>(&(*coordinates)[i + 1]);
          if (!x || !y || !std::isfinite(*x) || !std::isfinite(*y) ||
              *x < 0 || *y < 0 || *x > 10000 || *y > 10000) {
            result->Error("invalid_shape", "Invalid panel coordinates.");
            return;
          }
          points.push_back({static_cast<float>(*x * scale),
                            static_cast<float>(*y * scale)});
        }
        const bool applied = backdrop_->Apply(GetHandle(), points);
        result->Success(flutter::EncodableValue(applied));
      });

  // Desktop starts hidden; the tray icon opens the control panel.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  backdrop_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (backdrop_ && message == WM_WINDOWPOSCHANGED) backdrop_->Sync(hwnd);
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
