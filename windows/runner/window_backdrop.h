#ifndef RUNNER_WINDOW_BACKDROP_H_
#define RUNNER_WINDOW_BACKDROP_H_

#include <windows.h>
#include <d2d1.h>
#include <vector>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>

class WindowBackdrop {
 public:
  ~WindowBackdrop();
  bool Apply(HWND window, const std::vector<D2D1_POINT_2F>& outline);
  void Sync(HWND window);

 private:
  winrt::Windows::System::DispatcherQueueController dispatcher_{nullptr};
  winrt::Windows::UI::Composition::Compositor compositor_{nullptr};
  winrt::Windows::UI::Composition::Desktop::DesktopWindowTarget target_{nullptr};
  winrt::Windows::UI::Composition::SpriteVisual visual_{nullptr};
  winrt::com_ptr<ID2D1Factory> factory_;
  HWND window_ = nullptr;
};

#endif
