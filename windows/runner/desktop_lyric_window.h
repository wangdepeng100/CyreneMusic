#ifndef RUNNER_DESKTOP_LYRIC_WINDOW_H_
#define RUNNER_DESKTOP_LYRIC_WINDOW_H_

#include <windows.h>
#include <string>
#include <memory>
#include <functional>

// Desktop lyric window class
class DesktopLyricWindow {
 public:
  DesktopLyricWindow();
  ~DesktopLyricWindow();

  // Create desktop lyric window
  bool Create();
  
  // Destroy window
  void Destroy();
  
  // Show/Hide window
  void Show();
  void Hide();
  bool IsVisible() const;
  
  // Set lyric text
  void SetLyricText(const std::wstring& text);
  
  // Set window position
  void SetPosition(int x, int y);
  
  // Get window position
  void GetPosition(int* x, int* y);
  
  // Set font size
  void SetFontSize(int size);
  
  // Set text color (ARGB format)
  void SetTextColor(DWORD color);
  
  // Set stroke color (ARGB format)
  void SetStrokeColor(DWORD color);
  
  // Set stroke width
  void SetStrokeWidth(int width);
  
  // Set draggable
  void SetDraggable(bool draggable);
  
  // Set mouse transparent
  void SetMouseTransparent(bool transparent);
  
  // Set song info (title, artist, album cover URL)
  void SetSongInfo(const std::wstring& title, const std::wstring& artist, const std::wstring& album_cover);
  
  // Set playback control callback
  using PlaybackControlCallback = std::function<void(const std::string& action)>;
  void SetPlaybackControlCallback(PlaybackControlCallback callback);
  
  // Set playing state (for play/pause button icon)
  void SetPlayingState(bool is_playing);
  
  // Get window handle
  HWND GetHandle() const { return hwnd_; }

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  
  // Update window display
  void UpdateWindow();
  
  // Draw lyric to memory DC (handles both horizontal and vertical modes)
  void DrawLyric(HDC hdc, int width, int height);
  
  HWND hwnd_;
  std::wstring lyric_text_;
  std::wstring song_title_;
  std::wstring song_artist_;
  std::wstring album_cover_url_;
  int font_size_;
  DWORD text_color_;
  DWORD stroke_color_;
  int stroke_width_;
  bool is_draggable_;
  bool is_dragging_;
  POINT drag_point_;
  HFONT font_;
  
  // Control panel state
  bool is_hovered_;
  bool show_controls_;
  DWORD hover_start_time_;
  bool is_playing_;  // Current playback state
  
  // Button hit test areas
  RECT play_pause_button_rect_;
  RECT prev_button_rect_;
  RECT next_button_rect_;
  RECT font_size_up_rect_;
  RECT font_size_down_rect_;
  RECT color_picker_rect_;
  RECT translation_toggle_rect_;
  RECT close_button_rect_;
  
  // Translation display state
  bool show_translation_;
  std::wstring translation_text_;
  
  // Scrolling state for long text
  float lyric_scroll_offset_;
  float trans_scroll_offset_;
  bool lyric_needs_scroll_;
  bool trans_needs_scroll_;
  float lyric_text_width_;
  float trans_text_width_;
  DWORD last_scroll_time_;
  static const int kScrollPauseMs = 500;  // brief pause at start before scrolling
  DWORD lyric_scroll_pause_start_;
  DWORD trans_scroll_pause_start_;
  DWORD lyric_duration_ms_;  // Duration this lyric line will be displayed
  float lyric_scroll_speed_;  // Calculated scroll speed for current lyric
  float trans_scroll_speed_;  // Calculated scroll speed for translation
  
  // Playback control callback
  PlaybackControlCallback playback_callback_;
  
  // Helper methods
  bool IsPointInRect(const POINT& pt, const RECT& rect) const;
  void DrawControlPanel(HDC hdc, int width, int height);
  bool HandleButtonClick(const POINT& pt);  // Returns true if a button was clicked
  int GetControlPanelHeight() const;  // Dynamic height based on font size
  
 public:
  // Set translation text
  void SetTranslationText(const std::wstring& text);
  
  // Set show translation state
  void SetShowTranslation(bool show);
  
  // Get show translation state
  bool GetShowTranslation() const { return show_translation_; }
  
  // Set lyric duration (for calculating scroll speed)
  void SetLyricDuration(DWORD duration_ms);
  
  // Set vertical layout mode
  void SetVertical(bool vertical);
  
  // Get vertical layout mode
  bool GetVertical() const { return is_vertical_; }

 private:
  // Vertical layout mode
  bool is_vertical_;
  
  // Vertical mode button rect
  RECT vertical_toggle_rect_;
};

#endif  // RUNNER_DESKTOP_LYRIC_WINDOW_H_
