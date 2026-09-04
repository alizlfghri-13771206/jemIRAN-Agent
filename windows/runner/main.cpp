#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] =
    L"Local\\jemIRAN.Agent.6F723C0D-DF3C-45EE-9B58-4563EF074B67";
constexpr wchar_t kPrimaryWindowProperty[] = L"jemIRAN.Agent.PrimaryWindow";

BOOL CALLBACK FindPrimaryWindow(HWND window, LPARAM result) {
  if (::GetPropW(window, kPrimaryWindowProperty) != nullptr) {
    *reinterpret_cast<HWND*>(result) = window;
    return FALSE;
  }
  return TRUE;
}

HWND FindPrimaryInstanceWindow() {
  HWND primary = nullptr;

  // The first process may still be creating its Flutter window when the user
  // double-clicks the shortcut. Give it a short bounded window to publish the
  // handle instead of launching a second engine or silently doing nothing.
  for (int attempt = 0; attempt < 40 && primary == nullptr; ++attempt) {
    ::EnumWindows(FindPrimaryWindow, reinterpret_cast<LPARAM>(&primary));
    if (primary == nullptr) ::Sleep(50);
  }

  // If startup never reached the ready marker, activation can still use the
  // window handle.
  if (primary == nullptr) {
    primary = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"jemIRAN");
  }

  return primary;
}

void ActivatePrimaryWindow(HWND primary) {
  if (primary == nullptr) return;
  ::ShowWindowAsync(primary, SW_RESTORE);
  ::BringWindowToTop(primary);
  ::SetForegroundWindow(primary);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  const DWORD mutex_error = ::GetLastError();
  if (single_instance == nullptr) {
    // Fail closed: starting without the guard can recreate the duplicate-engine
    // bug. An elevated primary process may deny opening its mutex, so still try
    // to foreground its window before returning.
    ActivatePrimaryWindow(FindPrimaryInstanceWindow());
    return EXIT_FAILURE;
  }
  if (mutex_error == ERROR_ALREADY_EXISTS) {
    const HWND primary = FindPrimaryInstanceWindow();
    ::CloseHandle(single_instance);
    ActivatePrimaryWindow(primary);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(
          L"jemIRAN",
          origin, size)) {
    if (single_instance != nullptr) {
      ::ReleaseMutex(single_instance);
      ::CloseHandle(single_instance);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  ::SetPropW(window.GetHandle(), kPrimaryWindowProperty,
             reinterpret_cast<HANDLE>(1));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // DestroyWindow removes the HWND property automatically.
  ::ReleaseMutex(single_instance);
  ::CloseHandle(single_instance);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
