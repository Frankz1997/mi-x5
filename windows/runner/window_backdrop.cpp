#include "window_backdrop.h"

#include <DispatcherQueue.h>
#include <dwmapi.h>
#include <windows.graphics.interop.h>
#include <windows.ui.composition.interop.h>
#include <winrt/Windows.Graphics.h>
#include <cassert>

namespace {
LRESULT CALLBACK BackdropProcedure(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProcW(window, message, wparam, lparam);
}

class GeometrySource : public winrt::implements<
    GeometrySource, winrt::Windows::Graphics::IGeometrySource2D,
    ABI::Windows::Graphics::IGeometrySource2DInterop> {
 public:
  explicit GeometrySource(winrt::com_ptr<ID2D1PathGeometry> geometry)
      : geometry_(std::move(geometry)) {}

  HRESULT __stdcall GetGeometry(ID2D1Geometry** value) noexcept override {
    return geometry_->QueryInterface(__uuidof(ID2D1Geometry),
                                    reinterpret_cast<void**>(value));
  }

  HRESULT __stdcall TryGetGeometryUsingFactory(
      ID2D1Factory*, ID2D1Geometry** value) noexcept override {
    *value = nullptr;
    return S_OK;
  }

 private:
  winrt::com_ptr<ID2D1PathGeometry> geometry_;
};
}  // namespace

WindowBackdrop::~WindowBackdrop() {
  visual_ = nullptr;
  target_ = nullptr;
  compositor_ = nullptr;
  if (window_) DestroyWindow(window_);
}

void WindowBackdrop::Sync(HWND window) {
  if (!window_) return;
  if (!IsWindowVisible(window) || IsIconic(window)) {
    ShowWindow(window_, SW_HIDE);
    assert(!IsWindowVisible(window_));
    return;
  }
  RECT bounds;
  if (GetWindowRect(window, &bounds)) {
    if (SetWindowPos(window_, window, bounds.left, bounds.top,
                     bounds.right - bounds.left, bounds.bottom - bounds.top,
                     SWP_NOACTIVATE | SWP_SHOWWINDOW)) {
      assert(GetWindow(window_, GW_HWNDPREV) == window);
    }
  }
}

bool WindowBackdrop::Apply(HWND window,
                           const std::vector<D2D1_POINT_2F>& outline) {
  try {
    const DWORD no_border = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &no_border, sizeof(no_border));
    // Keep Flutter's fractional edge alpha; an HRGN would clip it to whole pixels.
    SetWindowRgn(window, nullptr, FALSE);
    if (!compositor_) {
      // Use a separate surface below Flutter; a target on its HWND replaces its content.
      WNDCLASSW window_class = {};
      window_class.lpfnWndProc = BackdropProcedure;
      window_class.hInstance = GetModuleHandleW(nullptr);
      window_class.lpszClassName = L"MiX5Backdrop";
      if (!RegisterClassW(&window_class) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        winrt::throw_last_error();
      }
      RECT bounds;
      GetWindowRect(window, &bounds);
      window_ = CreateWindowExW(
          WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_NOREDIRECTIONBITMAP |
              WS_EX_TRANSPARENT | WS_EX_TOPMOST,
          window_class.lpszClassName, L"Mi X5 backdrop", WS_POPUP,
          bounds.left, bounds.top, bounds.right - bounds.left,
          bounds.bottom - bounds.top, nullptr, nullptr, window_class.hInstance, nullptr);
      if (!window_) winrt::throw_last_error();
      const BOOL enable_host = TRUE;
      winrt::check_hresult(DwmSetWindowAttribute(
          window_, DWMWA_USE_HOSTBACKDROPBRUSH, &enable_host, sizeof(enable_host)));
      const MARGINS margins = {-1, -1, -1, -1};
      DwmExtendFrameIntoClientArea(window_, &margins);
      if (!winrt::Windows::System::DispatcherQueue::GetForCurrentThread()) {
        const DispatcherQueueOptions options = {
            sizeof(DispatcherQueueOptions), DQTYPE_THREAD_CURRENT, DQTAT_COM_STA};
        winrt::check_hresult(CreateDispatcherQueueController(
            options, reinterpret_cast<PDISPATCHERQUEUECONTROLLER*>(
                         winrt::put_abi(dispatcher_))));
      }
      compositor_ = winrt::Windows::UI::Composition::Compositor();
      auto interop = compositor_.as<
          ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>();
      winrt::check_hresult(interop->CreateDesktopWindowTarget(
          window_, FALSE, reinterpret_cast<
                             ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(
                             winrt::put_abi(target_))));
      winrt::check_hresult(D2D1CreateFactory(
          D2D1_FACTORY_TYPE_SINGLE_THREADED, factory_.put()));
      visual_ = compositor_.CreateSpriteVisual();
      visual_.Brush(compositor_.CreateHostBackdropBrush());
      target_.Root(visual_);
    }

    winrt::com_ptr<ID2D1PathGeometry> shape;
    winrt::check_hresult(factory_->CreatePathGeometry(shape.put()));
    winrt::com_ptr<ID2D1GeometrySink> sink;
    winrt::check_hresult(shape->Open(sink.put()));
    sink->SetFillMode(D2D1_FILL_MODE_WINDING);
    sink->BeginFigure(outline.front(), D2D1_FIGURE_BEGIN_FILLED);
    sink->AddLines(outline.data() + 1, static_cast<UINT32>(outline.size() - 1));
    sink->EndFigure(D2D1_FIGURE_END_CLOSED);
    winrt::check_hresult(sink->Close());
    auto geometry = compositor_.CreatePathGeometry();
    geometry.Path(winrt::Windows::UI::Composition::CompositionPath(
        winrt::make<GeometrySource>(std::move(shape))));
    visual_.Clip(compositor_.CreateGeometricClip(geometry));
    RECT bounds;
    GetClientRect(window, &bounds);
    visual_.Size({static_cast<float>(bounds.right - bounds.left),
                  static_cast<float>(bounds.bottom - bounds.top)});
    visual_.Opacity(1);
    Sync(window);
    return true;
  } catch (const winrt::hresult_error&) {
    visual_ = nullptr;
    target_ = nullptr;
    compositor_ = nullptr;
    factory_ = nullptr;
    if (window_) {
      DestroyWindow(window_);
      window_ = nullptr;
    }
    return false;
  }
}
