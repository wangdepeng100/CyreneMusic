#include "desktop_lyric_window.h"
#include <dwmapi.h>
#include <gdiplus.h>
#include <windowsx.h>
#include <algorithm>

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "gdiplus.lib")

namespace {
const wchar_t kWindowClassName[] = L"DESKTOP_LYRIC_WINDOW";
const int kDefaultFontSize = 32;
const DWORD kDefaultTextColor = 0xFFFFFFFF;  // White
const DWORD kDefaultStrokeColor = 0xFF000000;  // Black
const int kDefaultStrokeWidth = 2;
const int kWindowWidth = 800;
const int kWindowHeight = 100;
const int kControlPanelHeight = 180;  // Height when showing controls
const int kHoverDelay = 300;  // ms to wait before showing controls

// GDI+ initialization
ULONG_PTR gdiplusToken = 0;

void InitGdiPlus() {
  if (gdiplusToken == 0) {
    Gdiplus::GdiplusStartupInput gdiplusStartupInput;
    Gdiplus::GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, nullptr);
  }
}

void ShutdownGdiPlus() {
  if (gdiplusToken != 0) {
    Gdiplus::GdiplusShutdown(gdiplusToken);
    gdiplusToken = 0;
  }
}

// Check if a character is CJK (Chinese, Japanese, Korean)
bool IsCJKCharacter(wchar_t ch) {
  // CJK Unified Ideographs
  if (ch >= 0x4E00 && ch <= 0x9FFF) return true;
  // CJK Unified Ideographs Extension A
  if (ch >= 0x3400 && ch <= 0x4DBF) return true;
  // Hiragana
  if (ch >= 0x3040 && ch <= 0x309F) return true;
  // Katakana
  if (ch >= 0x30A0 && ch <= 0x30FF) return true;
  // Full-width characters
  if (ch >= 0xFF00 && ch <= 0xFFEF) return true;
  // CJK Symbols and Punctuation
  if (ch >= 0x3000 && ch <= 0x303F) return true;
  // Hangul (Korean)
  if (ch >= 0xAC00 && ch <= 0xD7AF) return true;
  // CJK Compatibility Ideographs
  if (ch >= 0xF900 && ch <= 0xFAFF) return true;
  return false;
}

// Draw a single character with optional rotation (for CJK in vertical mode)
void DrawCharWithRotation(Gdiplus::Graphics& graphics, wchar_t ch, 
                          Gdiplus::FontFamily* fontFamily, int fontSize, int strokeWidth,
                          DWORD textColor, DWORD strokeColor,
                          float x, float y, float charWidth, float charHeight,
                          bool rotateCJK) {
  wchar_t str[2] = { ch, 0 };
  
  bool isCJK = IsCJKCharacter(ch);
  bool needRotate = rotateCJK && isCJK;
  
  Gdiplus::GraphicsState state = graphics.Save();
  
  if (needRotate) {
    // Rotate CJK character -90° (counter-clockwise) around its center
    // This makes CJK characters appear upright in vertical mode
    float centerX = x + charWidth / 2;
    float centerY = y + charHeight / 2;
    graphics.TranslateTransform(centerX, centerY);
    graphics.RotateTransform(-90.0f);
    graphics.TranslateTransform(-centerX, -centerY);
  }
  
  Gdiplus::StringFormat format;
  format.SetAlignment(Gdiplus::StringAlignmentCenter);
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  
  Gdiplus::RectF charRect(x, y, charWidth, charHeight);
  
  if (strokeWidth > 0) {
    Gdiplus::GraphicsPath path;
    path.AddString(str, -1, fontFamily, Gdiplus::FontStyleBold, 
                   static_cast<Gdiplus::REAL>(fontSize), charRect, &format);
    
    Gdiplus::Pen strokePen(Gdiplus::Color(
        (strokeColor >> 24) & 0xFF, (strokeColor >> 16) & 0xFF,
        (strokeColor >> 8) & 0xFF, strokeColor & 0xFF
    ), static_cast<Gdiplus::REAL>(strokeWidth));
    strokePen.SetLineJoin(Gdiplus::LineJoinRound);
    graphics.DrawPath(&strokePen, &path);
    
    Gdiplus::SolidBrush fillBrush(Gdiplus::Color(
        (textColor >> 24) & 0xFF, (textColor >> 16) & 0xFF,
        (textColor >> 8) & 0xFF, textColor & 0xFF
    ));
    graphics.FillPath(&fillBrush, &path);
  } else {
    Gdiplus::Font font(fontFamily, static_cast<Gdiplus::REAL>(fontSize), 
                       Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::SolidBrush textBrush(Gdiplus::Color(
        (textColor >> 24) & 0xFF, (textColor >> 16) & 0xFF,
        (textColor >> 8) & 0xFF, textColor & 0xFF
    ));
    graphics.DrawString(str, -1, &font, charRect, &format, &textBrush);
  }
  
  graphics.Restore(state);
}

// Draw a segment of non-CJK text (Latin characters) as a continuous string
void DrawLatinSegment(Gdiplus::Graphics& graphics, const std::wstring& segment,
                      Gdiplus::FontFamily* fontFamily, int fontSize, int strokeWidth,
                      DWORD textColor, DWORD strokeColor,
                      float x, float y, float height) {
  Gdiplus::Font font(fontFamily, static_cast<Gdiplus::REAL>(fontSize), 
                     Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  
  // Measure segment width
  Gdiplus::RectF measureRect(0, 0, 10000, height);
  Gdiplus::RectF bounds;
  Gdiplus::StringFormat measureFormat;
  graphics.MeasureString(segment.c_str(), -1, &font, measureRect, &measureFormat, &bounds);
  
  Gdiplus::StringFormat format;
  format.SetAlignment(Gdiplus::StringAlignmentNear);
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  
  Gdiplus::RectF textRect(x, y, bounds.Width, height);
  
  if (strokeWidth > 0) {
    Gdiplus::GraphicsPath path;
    path.AddString(segment.c_str(), -1, fontFamily, Gdiplus::FontStyleBold,
                   static_cast<Gdiplus::REAL>(fontSize), textRect, &format);
    
    Gdiplus::Pen strokePen(Gdiplus::Color(
        (strokeColor >> 24) & 0xFF, (strokeColor >> 16) & 0xFF,
        (strokeColor >> 8) & 0xFF, strokeColor & 0xFF
    ), static_cast<Gdiplus::REAL>(strokeWidth));
    strokePen.SetLineJoin(Gdiplus::LineJoinRound);
    graphics.DrawPath(&strokePen, &path);
    
    Gdiplus::SolidBrush fillBrush(Gdiplus::Color(
        (textColor >> 24) & 0xFF, (textColor >> 16) & 0xFF,
        (textColor >> 8) & 0xFF, textColor & 0xFF
    ));
    graphics.FillPath(&fillBrush, &path);
  } else {
    Gdiplus::SolidBrush textBrush(Gdiplus::Color(
        (textColor >> 24) & 0xFF, (textColor >> 16) & 0xFF,
        (textColor >> 8) & 0xFF, textColor & 0xFF
    ));
    graphics.DrawString(segment.c_str(), -1, &font, textRect, &format, &textBrush);
  }
}

// Draw text with per-character rotation for CJK in vertical mode
// Latin characters are drawn as continuous strings to preserve proper spacing
void DrawVerticalModeText(Gdiplus::Graphics& graphics, const std::wstring& text,
                          Gdiplus::FontFamily* fontFamily, int fontSize, int strokeWidth,
                          DWORD textColor, DWORD strokeColor,
                          float startX, float y, float height, float scrollOffset = 0.0f) {
  Gdiplus::Font measureFont(fontFamily, static_cast<Gdiplus::REAL>(fontSize), 
                            Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::RectF measureRect(0, 0, 10000, static_cast<Gdiplus::REAL>(height));
  Gdiplus::StringFormat measureFormat;
  
  float x = startX - scrollOffset;
  size_t i = 0;
  
  while (i < text.length()) {
    wchar_t ch = text[i];
    
    if (IsCJKCharacter(ch)) {
      // Draw CJK character with rotation
      wchar_t str[2] = { ch, 0 };
      Gdiplus::RectF charBounds;
      graphics.MeasureString(str, -1, &measureFont, measureRect, &measureFormat, &charBounds);
      float charWidth = charBounds.Width > 0 ? charBounds.Width : fontSize * 1.0f;
      
      DrawCharWithRotation(graphics, ch, fontFamily, fontSize, strokeWidth,
                           textColor, strokeColor, x, y, charWidth, height, true);
      x += charWidth;
      i++;
    } else {
      // Collect consecutive non-CJK characters
      std::wstring latinSegment;
      while (i < text.length() && !IsCJKCharacter(text[i])) {
        latinSegment += text[i];
        i++;
      }
      
      // Measure the segment width
      Gdiplus::RectF segmentBounds;
      graphics.MeasureString(latinSegment.c_str(), -1, &measureFont, measureRect, &measureFormat, &segmentBounds);
      
      // Draw the Latin segment as a continuous string (no rotation)
      DrawLatinSegment(graphics, latinSegment, fontFamily, fontSize, strokeWidth,
                       textColor, strokeColor, x, y, height);
      
      x += segmentBounds.Width;
    }
  }
}

// Helper to apply -90° rotation around a point for button icons in vertical mode
// Returns the saved graphics state for later restoration
Gdiplus::GraphicsState ApplyButtonRotation(Gdiplus::Graphics& graphics, bool isVertical, 
                                            float centerX, float centerY) {
  Gdiplus::GraphicsState state = graphics.Save();
  if (isVertical) {
    graphics.TranslateTransform(centerX, centerY);
    graphics.RotateTransform(-90.0f);
    graphics.TranslateTransform(-centerX, -centerY);
  }
  return state;
}

}  // namespace

DesktopLyricWindow::DesktopLyricWindow()
    : hwnd_(nullptr),
      lyric_text_(L""),
      song_title_(L""),
      song_artist_(L""),
      album_cover_url_(L""),
      font_size_(kDefaultFontSize),
      text_color_(kDefaultTextColor),
      stroke_color_(kDefaultStrokeColor),
      stroke_width_(kDefaultStrokeWidth),
      is_draggable_(true),
      is_dragging_(false),
      font_(nullptr),
      is_hovered_(false),
      show_controls_(false),
      hover_start_time_(0),
      is_playing_(false),
      show_translation_(true),
      translation_text_(L""),
      lyric_scroll_offset_(0.0f),
      trans_scroll_offset_(0.0f),
      lyric_needs_scroll_(false),
      trans_needs_scroll_(false),
      lyric_text_width_(0.0f),
      trans_text_width_(0.0f),
      last_scroll_time_(0),
      lyric_scroll_pause_start_(0),
      trans_scroll_pause_start_(0),
      lyric_duration_ms_(3000),  // Default 3 seconds
      lyric_scroll_speed_(0.0f),
      trans_scroll_speed_(0.0f),
      playback_callback_(nullptr),
      is_vertical_(false) {
  InitGdiPlus();
  
  // Initialize button rects
  memset(&play_pause_button_rect_, 0, sizeof(RECT));
  memset(&prev_button_rect_, 0, sizeof(RECT));
  memset(&next_button_rect_, 0, sizeof(RECT));
  memset(&font_size_up_rect_, 0, sizeof(RECT));
  memset(&font_size_down_rect_, 0, sizeof(RECT));
  memset(&color_picker_rect_, 0, sizeof(RECT));
  memset(&translation_toggle_rect_, 0, sizeof(RECT));
  memset(&close_button_rect_, 0, sizeof(RECT));
  memset(&vertical_toggle_rect_, 0, sizeof(RECT));
}

DesktopLyricWindow::~DesktopLyricWindow() {
  Destroy();
  ShutdownGdiPlus();
}

bool DesktopLyricWindow::Create() {
  if (hwnd_ != nullptr) {
    return true;  // Window already exists
  }

  // Register window class
  WNDCLASSEX wc = {};
  wc.cbSize = sizeof(WNDCLASSEX);
  wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;  // Enable double-click
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.lpszClassName = kWindowClassName;
  
  if (!RegisterClassEx(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    return false;
  }

  // Get screen size
  int screen_width = GetSystemMetrics(SM_CXSCREEN);
  int screen_height = GetSystemMetrics(SM_CYSCREEN);
  
  // Default position: center bottom
  int x = (screen_width - kWindowWidth) / 2;
  int y = screen_height - kWindowHeight - 100;

  // Create layered window
  hwnd_ = CreateWindowEx(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kWindowClassName,
      L"Desktop Lyric",
      WS_POPUP,
      x, y, kWindowWidth, kWindowHeight,
      nullptr,
      nullptr,
      GetModuleHandle(nullptr),
      this);

  if (hwnd_ == nullptr) {
    return false;
  }

  // Save this pointer
  SetWindowLongPtr(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  // Create font
  font_ = CreateFont(
      font_size_, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
      L"Microsoft YaHei");

  return true;
}

void DesktopLyricWindow::Destroy() {
  if (hwnd_ != nullptr) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  
  if (font_ != nullptr) {
    DeleteObject(font_);
    font_ = nullptr;
  }
}

void DesktopLyricWindow::Show() {
  if (hwnd_ != nullptr) {
    UpdateWindow();
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  }
}

void DesktopLyricWindow::Hide() {
  if (hwnd_ != nullptr) {
    ShowWindow(hwnd_, SW_HIDE);
  }
}

bool DesktopLyricWindow::IsVisible() const {
  return hwnd_ != nullptr && IsWindowVisible(hwnd_);
}

void DesktopLyricWindow::SetLyricText(const std::wstring& text) {
  // Reset scroll state when lyric changes
  if (lyric_text_ != text) {
    lyric_scroll_offset_ = 0.0f;
    lyric_needs_scroll_ = false;
    lyric_text_width_ = 0.0f;
    lyric_scroll_pause_start_ = GetTickCount();
    lyric_scroll_speed_ = 0.0f;  // Will be calculated in DrawLyric
  }
  lyric_text_ = text;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetLyricDuration(DWORD duration_ms) {
  lyric_duration_ms_ = duration_ms > 0 ? duration_ms : 3000;
}

void DesktopLyricWindow::SetPosition(int x, int y) {
  if (hwnd_ != nullptr) {
    SetWindowPos(hwnd_, HWND_TOPMOST, x, y, 0, 0, 
                 SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

void DesktopLyricWindow::GetPosition(int* x, int* y) {
  if (hwnd_ != nullptr) {
    RECT rect;
    GetWindowRect(hwnd_, &rect);
    *x = rect.left;
    *y = rect.top;
  }
}

void DesktopLyricWindow::SetFontSize(int size) {
  font_size_ = size;
  
  // Recreate font
  if (font_ != nullptr) {
    DeleteObject(font_);
  }
  
  font_ = CreateFont(
      font_size_, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
      L"Microsoft YaHei");
  
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetTextColor(DWORD color) {
  text_color_ = color;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetStrokeColor(DWORD color) {
  stroke_color_ = color;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetStrokeWidth(int width) {
  stroke_width_ = width;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetDraggable(bool draggable) {
  is_draggable_ = draggable;
}

void DesktopLyricWindow::SetMouseTransparent(bool transparent) {
  if (hwnd_ == nullptr) return;
  
  LONG exStyle = GetWindowLong(hwnd_, GWL_EXSTYLE);
  if (transparent) {
    exStyle |= WS_EX_TRANSPARENT;
  } else {
    exStyle &= ~WS_EX_TRANSPARENT;
  }
  SetWindowLong(hwnd_, GWL_EXSTYLE, exStyle);
}

void DesktopLyricWindow::SetSongInfo(const std::wstring& title, const std::wstring& artist, const std::wstring& album_cover) {
  song_title_ = title;
  song_artist_ = artist;
  album_cover_url_ = album_cover;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetPlaybackControlCallback(PlaybackControlCallback callback) {
  playback_callback_ = callback;
}

void DesktopLyricWindow::SetPlayingState(bool is_playing) {
  is_playing_ = is_playing;
  if (IsVisible() && show_controls_) {
    UpdateWindow();  // Refresh to show updated button icon
  }
}

int DesktopLyricWindow::GetControlPanelHeight() const {
  // Calculate height based on font size:
  // - Header area (song title + artist): ~70px
  // - Lyric area: font_size_ + padding (~10px)
  // - Translation area (if enabled): font_size_ * 0.7 + 5
  // - Button row 1: ~46px (36 button + 10 spacing)
  // - Button row 2: ~38px (28 button + 10 spacing)
  // - Bottom padding: ~15px
  int height = 70 + font_size_ + 10;
  if (show_translation_ && !translation_text_.empty()) {
    height += static_cast<int>(font_size_ * 0.7f) + 5;
  }
  height += 15 + 36 + 10 + 28 + 15;  // spacing + row1 + gap + row2 + bottom
  return height;
}

void DesktopLyricWindow::UpdateWindow() {
  if (hwnd_ == nullptr) return;

  int current_width, current_height;
  
  // Calculate "logical" horizontal dimensions first
  int logical_width = kWindowWidth;
  int logical_height;
  
  if (show_controls_) {
    logical_height = GetControlPanelHeight();
  } else {
    // Normal mode: adjust height based on whether translation is shown
    bool hasTranslation = show_translation_ && !translation_text_.empty();
    if (hasTranslation) {
      logical_height = kWindowHeight + static_cast<int>(font_size_ * 0.6f) + 10;
    } else {
      logical_height = kWindowHeight;
    }
  }
  
  if (is_vertical_) {
    // Vertical mode: swap width and height (rotate 90°)
    current_width = logical_height;
    current_height = logical_width;
  } else {
    // Horizontal mode: use logical dimensions directly
    current_width = logical_width;
    current_height = logical_height;
  }

  // Create memory DC
  HDC hdc_screen = GetDC(nullptr);
  HDC hdc_mem = CreateCompatibleDC(hdc_screen);
  
  // Create 32-bit bitmap with dynamic size
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = current_width;
  bmi.bmiHeader.biHeight = -current_height;  // Negative means top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  
  void* bits = nullptr;
  HBITMAP hbm = CreateDIBSection(hdc_mem, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  HBITMAP hbm_old = (HBITMAP)SelectObject(hdc_mem, hbm);
  
  // Draw lyric with dynamic size
  DrawLyric(hdc_mem, current_width, current_height);
  
  // Update layered window with dynamic size
  POINT pt_src = {0, 0};
  SIZE size = {current_width, current_height};
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  
  UpdateLayeredWindow(hwnd_, hdc_screen, nullptr, &size, hdc_mem, &pt_src,
                      0, &blend, ULW_ALPHA);
  
  // Cleanup
  SelectObject(hdc_mem, hbm_old);
  DeleteObject(hbm);
  DeleteDC(hdc_mem);
  ReleaseDC(nullptr, hdc_screen);
}

void DesktopLyricWindow::DrawLyric(HDC hdc, int width, int height) {
  // Use GDI+ to draw text (better anti-aliasing and stroke)
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
  
  // Clear background (transparent)
  graphics.Clear(Gdiplus::Color(0, 0, 0, 0));
  
  // In vertical mode, apply 90° clockwise rotation
  // This rotates the horizontal layout to become vertical
  int draw_width = width;
  int draw_height = height;
  if (is_vertical_) {
    // Rotate 90° clockwise: (x,y) -> (height-y, x)
    // We'll draw in "logical horizontal" space with swapped dimensions
    draw_width = height;
    draw_height = width;
    
    // Apply rotation transform
    graphics.TranslateTransform(static_cast<Gdiplus::REAL>(width) / 2.0f, 
                                 static_cast<Gdiplus::REAL>(height) / 2.0f);
    graphics.RotateTransform(90.0f);
    graphics.TranslateTransform(-static_cast<Gdiplus::REAL>(height) / 2.0f, 
                                 -static_cast<Gdiplus::REAL>(width) / 2.0f);
  }
  
  // Show control panel on hover (works in both horizontal and vertical modes)
  if (show_controls_) {
    DrawControlPanel(hdc, draw_width, draw_height);
    return;
  }
  
  if (lyric_text_.empty()) {
    return;
  }
  
  // Create font
  Gdiplus::FontFamily fontFamily(L"Microsoft YaHei");
  Gdiplus::Font font(&fontFamily, static_cast<Gdiplus::REAL>(font_size_), 
                     Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  
  // Calculate layout based on whether translation is shown
  bool hasTranslation = show_translation_ && !translation_text_.empty();
  int lyric_height = font_size_ + 10;
  int trans_height = hasTranslation ? static_cast<int>(font_size_ * 0.6f) + 5 : 0;
  int total_content_height = lyric_height + trans_height;
  int start_y = (draw_height - total_content_height) / 2;
  
  // Measure lyric text width
  Gdiplus::RectF measureRect(0, 0, 10000, static_cast<Gdiplus::REAL>(lyric_height));
  Gdiplus::RectF lyricBounds;
  Gdiplus::StringFormat measureFormat;
  measureFormat.SetAlignment(Gdiplus::StringAlignmentNear);
  measureFormat.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  graphics.MeasureString(lyric_text_.c_str(), -1, &font, measureRect, &measureFormat, &lyricBounds);
  lyric_text_width_ = lyricBounds.Width;
  
  // Check if lyric needs scrolling (with some padding)
  const float padding = 40.0f;
  lyric_needs_scroll_ = lyric_text_width_ > (draw_width - padding);
  
  // Calculate scroll offset for lyric
  DWORD currentTime = GetTickCount();
  float lyric_x_offset = 0.0f;
  
  if (lyric_needs_scroll_) {
    float maxScroll = lyric_text_width_ - draw_width + padding;
    
    // Calculate scroll speed if not yet calculated
    // Speed = distance / (available_time - pause_time)
    // Use 90% of duration to ensure completion before next lyric
    if (lyric_scroll_speed_ <= 0.0f && maxScroll > 0) {
      float available_time_ms = lyric_duration_ms_ * 0.9f - kScrollPauseMs;
      if (available_time_ms > 100) {  // At least 100ms for scrolling
        lyric_scroll_speed_ = maxScroll / (available_time_ms / 1000.0f);
      } else {
        lyric_scroll_speed_ = maxScroll * 2.0f;  // Fast scroll if very short duration
      }
    }
    
    // Initial pause before scrolling starts
    if (lyric_scroll_pause_start_ > 0) {
      if (currentTime - lyric_scroll_pause_start_ >= kScrollPauseMs) {
        lyric_scroll_pause_start_ = 0;  // End pause, start scrolling
      }
    } else if (lyric_scroll_offset_ < maxScroll) {
      // Scroll from left to right (only once)
      float scrollDelta = lyric_scroll_speed_ * (currentTime - last_scroll_time_) / 1000.0f;
      lyric_scroll_offset_ += scrollDelta;
      if (lyric_scroll_offset_ > maxScroll) {
        lyric_scroll_offset_ = maxScroll;  // Stop at the end
      }
    }
    lyric_x_offset = -lyric_scroll_offset_;
  }
  
  // Layout rect for main lyric (with scroll offset)
  Gdiplus::StringFormat format;
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  
  if (lyric_needs_scroll_) {
    format.SetAlignment(Gdiplus::StringAlignmentNear);
  } else {
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
  }
  
  Gdiplus::RectF lyricRect(
    lyric_needs_scroll_ ? lyric_x_offset + padding / 2 : 0,
    static_cast<Gdiplus::REAL>(start_y), 
    lyric_needs_scroll_ ? lyric_text_width_ + padding : static_cast<Gdiplus::REAL>(draw_width), 
    static_cast<Gdiplus::REAL>(lyric_height)
  );
  
  // Set clipping region to prevent text from drawing outside window
  graphics.SetClip(Gdiplus::RectF(0, static_cast<Gdiplus::REAL>(start_y), 
                                   static_cast<Gdiplus::REAL>(draw_width), 
                                   static_cast<Gdiplus::REAL>(lyric_height)));
  
  // Draw main lyric
  if (is_vertical_) {
    // In vertical mode, draw character by character with CJK rotation
    Gdiplus::FontFamily lyricFontFamily(L"Microsoft YaHei");
    float startX = lyric_needs_scroll_ ? padding / 2 : (draw_width - lyric_text_width_) / 2;
    DrawVerticalModeText(graphics, lyric_text_, &lyricFontFamily, font_size_, stroke_width_,
                         text_color_, stroke_color_, startX, 
                         static_cast<float>(start_y), static_cast<float>(lyric_height),
                         lyric_scroll_offset_);
  } else {
    // Horizontal mode: draw as before
    if (stroke_width_ > 0) {
      Gdiplus::GraphicsPath path;
      Gdiplus::FontFamily fontFamilyPath(L"Microsoft YaHei");
      path.AddString(lyric_text_.c_str(), -1, &fontFamilyPath, 
                     Gdiplus::FontStyleBold, static_cast<Gdiplus::REAL>(font_size_),
                     lyricRect, &format);
      
      Gdiplus::Pen stroke_pen(Gdiplus::Color(
          (stroke_color_ >> 24) & 0xFF,
          (stroke_color_ >> 16) & 0xFF,
          (stroke_color_ >> 8) & 0xFF,
          stroke_color_ & 0xFF
      ), static_cast<Gdiplus::REAL>(stroke_width_));
      
      stroke_pen.SetLineJoin(Gdiplus::LineJoinRound);
      graphics.DrawPath(&stroke_pen, &path);
      
      Gdiplus::SolidBrush text_brush(Gdiplus::Color(
          (text_color_ >> 24) & 0xFF,
          (text_color_ >> 16) & 0xFF,
          (text_color_ >> 8) & 0xFF,
          text_color_ & 0xFF
      ));
      graphics.FillPath(&text_brush, &path);
    } else {
      Gdiplus::SolidBrush text_brush(Gdiplus::Color(
          (text_color_ >> 24) & 0xFF,
          (text_color_ >> 16) & 0xFF,
          (text_color_ >> 8) & 0xFF,
          text_color_ & 0xFF
      ));
      graphics.DrawString(lyric_text_.c_str(), -1, &font, lyricRect, &format, &text_brush);
    }
  }
  
  // Reset clipping
  graphics.ResetClip();
  
  // Draw translation if enabled and available
  if (hasTranslation) {
    Gdiplus::Font trans_font(&fontFamily, static_cast<Gdiplus::REAL>(font_size_ * 0.6f), 
                              Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    
    // Measure translation text width
    Gdiplus::RectF transMeasureRect(0, 0, 10000, static_cast<Gdiplus::REAL>(trans_height));
    Gdiplus::RectF transBounds;
    graphics.MeasureString(translation_text_.c_str(), -1, &trans_font, transMeasureRect, &measureFormat, &transBounds);
    trans_text_width_ = transBounds.Width;
    
    // Check if translation needs scrolling
    trans_needs_scroll_ = trans_text_width_ > (draw_width - padding);
    
    // Calculate scroll offset for translation
    float trans_x_offset = 0.0f;
    
    if (trans_needs_scroll_) {
      float maxTransScroll = trans_text_width_ - draw_width + padding;
      
      // Calculate scroll speed for translation (same timing as lyric)
      if (trans_scroll_speed_ <= 0.0f && maxTransScroll > 0) {
        float available_time_ms = lyric_duration_ms_ * 0.9f - kScrollPauseMs;
        if (available_time_ms > 100) {
          trans_scroll_speed_ = maxTransScroll / (available_time_ms / 1000.0f);
        } else {
          trans_scroll_speed_ = maxTransScroll * 2.0f;
        }
      }
      
      // Initial pause before scrolling starts
      if (trans_scroll_pause_start_ > 0) {
        if (currentTime - trans_scroll_pause_start_ >= kScrollPauseMs) {
          trans_scroll_pause_start_ = 0;  // End pause, start scrolling
        }
      } else if (trans_scroll_offset_ < maxTransScroll) {
        // Scroll from left to right (only once)
        float scrollDelta = trans_scroll_speed_ * (currentTime - last_scroll_time_) / 1000.0f;
        trans_scroll_offset_ += scrollDelta;
        if (trans_scroll_offset_ > maxTransScroll) {
          trans_scroll_offset_ = maxTransScroll;  // Stop at the end
        }
      }
      trans_x_offset = -trans_scroll_offset_;
    }
    
    Gdiplus::StringFormat transFormat;
    transFormat.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    if (trans_needs_scroll_) {
      transFormat.SetAlignment(Gdiplus::StringAlignmentNear);
    } else {
      transFormat.SetAlignment(Gdiplus::StringAlignmentCenter);
    }
    
    Gdiplus::RectF transRect(
      trans_needs_scroll_ ? trans_x_offset + padding / 2 : 0,
      static_cast<Gdiplus::REAL>(start_y + lyric_height), 
      trans_needs_scroll_ ? trans_text_width_ + padding : static_cast<Gdiplus::REAL>(draw_width), 
      static_cast<Gdiplus::REAL>(trans_height)
    );
    
    // Set clipping for translation
    graphics.SetClip(Gdiplus::RectF(0, static_cast<Gdiplus::REAL>(start_y + lyric_height), 
                                     static_cast<Gdiplus::REAL>(draw_width), 
                                     static_cast<Gdiplus::REAL>(trans_height)));
    
    // Translation text color (slightly transparent)
    DWORD trans_text_color = (200 << 24) | ((text_color_ >> 16) & 0xFF) << 16 | 
                             ((text_color_ >> 8) & 0xFF) << 8 | (text_color_ & 0xFF);
    
    if (is_vertical_) {
      // In vertical mode, draw character by character with CJK rotation
      Gdiplus::FontFamily transFontFamily(L"Microsoft YaHei");
      int trans_font_size = static_cast<int>(font_size_ * 0.6f);
      int trans_stroke = static_cast<int>(stroke_width_ * 0.7f);
      float transStartX = trans_needs_scroll_ ? padding / 2 : (draw_width - trans_text_width_) / 2;
      DrawVerticalModeText(graphics, translation_text_, &transFontFamily, trans_font_size, trans_stroke,
                           trans_text_color, stroke_color_, transStartX,
                           static_cast<float>(start_y + lyric_height), static_cast<float>(trans_height),
                           trans_scroll_offset_);
    } else {
      // Horizontal mode: draw as before
      if (stroke_width_ > 0) {
        Gdiplus::GraphicsPath trans_path;
        trans_path.AddString(translation_text_.c_str(), -1, &fontFamily, 
                             Gdiplus::FontStyleRegular, static_cast<Gdiplus::REAL>(font_size_ * 0.6f),
                             transRect, &transFormat);
        
        Gdiplus::Pen trans_stroke_pen(Gdiplus::Color(
            (stroke_color_ >> 24) & 0xFF,
            (stroke_color_ >> 16) & 0xFF,
            (stroke_color_ >> 8) & 0xFF,
            stroke_color_ & 0xFF
        ), static_cast<Gdiplus::REAL>(stroke_width_ * 0.7f));
        trans_stroke_pen.SetLineJoin(Gdiplus::LineJoinRound);
        graphics.DrawPath(&trans_stroke_pen, &trans_path);
        
        Gdiplus::SolidBrush trans_brush(Gdiplus::Color(
            200,
            (text_color_ >> 16) & 0xFF,
            (text_color_ >> 8) & 0xFF,
            text_color_ & 0xFF
        ));
        graphics.FillPath(&trans_brush, &trans_path);
      } else {
        Gdiplus::SolidBrush trans_brush(Gdiplus::Color(
            200,
            (text_color_ >> 16) & 0xFF,
            (text_color_ >> 8) & 0xFF,
            text_color_ & 0xFF
        ));
        graphics.DrawString(translation_text_.c_str(), -1, &trans_font, transRect, &transFormat, &trans_brush);
      }
    }
    
    graphics.ResetClip();
  }
  
  // Update last scroll time
  last_scroll_time_ = currentTime;
  
  // Check if scrolling is still in progress
  bool lyric_still_scrolling = lyric_needs_scroll_ && 
      (lyric_scroll_pause_start_ > 0 || lyric_scroll_offset_ < lyric_text_width_ - draw_width + padding);
  bool trans_still_scrolling = trans_needs_scroll_ && 
      (trans_scroll_pause_start_ > 0 || trans_scroll_offset_ < trans_text_width_ - draw_width + padding);
  
  // If scrolling is in progress, set a timer to refresh
  if ((lyric_still_scrolling || trans_still_scrolling) && hwnd_ != nullptr && !show_controls_) {
    SetTimer(hwnd_, 2, 30, nullptr);  // ~33fps refresh for smooth scrolling
  } else {
    KillTimer(hwnd_, 2);
  }
}

LRESULT CALLBACK DesktopLyricWindow::WndProc(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam) {
  DesktopLyricWindow* window = 
      reinterpret_cast<DesktopLyricWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  
  if (window == nullptr) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }
  
  switch (message) {
    case WM_LBUTTONDBLCLK: {
      // Double-click to toggle vertical mode (especially useful in vertical mode where controls are hidden)
      if (window->playback_callback_) {
        window->playback_callback_("toggle_vertical");
      }
      return 0;
    }
    
    case WM_LBUTTONDOWN: {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      POINT originalPt = pt;  // Keep original for dragging
      bool button_clicked = false;
      
      if (window->show_controls_) {
        // In vertical mode, transform mouse coordinates from actual to logical space
        // The control panel is drawn in rotated coordinates, so we need to inverse transform
        if (window->is_vertical_) {
          // Get actual window dimensions
          RECT windowRect;
          GetClientRect(hwnd, &windowRect);
          int actual_width = windowRect.right;   // = logical_height (control panel height)
          int actual_height = windowRect.bottom; // = logical_width (800)
          
          // The drawing transform in DrawControlPanel is:
          // 1. Translate to (actual_width/2, actual_height/2)
          // 2. Rotate 90° clockwise
          // 3. Translate by (-actual_height/2, -actual_width/2)
          // 
          // For a logical point (lx, ly):
          //   After transform: ax = ly, ay = actual_height - lx
          // 
          // Inverse transform: lx = actual_height - ay, ly = ax
          // But our logical coordinate system origin is different!
          // 
          // Actually the DrawControlPanel uses width/height params as logical dimensions
          // In vertical mode: width param = logical_width, height param = logical_height
          // The rotation center is at (actual_width/2, actual_height/2) in bitmap coords
          // 
          // Correct inverse: lx = actual_height - pt.y, ly = pt.x
          POINT logicalPt;
          logicalPt.x = actual_height - pt.y;
          logicalPt.y = pt.x;
          
          // Debug output
          wchar_t dbg[256];
          swprintf_s(dbg, L"[DesktopLyric] Click: actual(%d,%d) -> logical(%d,%d), window(%dx%d)\n",
                     pt.x, pt.y, logicalPt.x, logicalPt.y, actual_width, actual_height);
          OutputDebugStringW(dbg);
          
          button_clicked = window->HandleButtonClick(logicalPt);
        } else {
          button_clicked = window->HandleButtonClick(pt);
        }
      }
      
      // If not clicking a button and draggable, start dragging (use original coordinates)
      if (!button_clicked && window->is_draggable_) {
        window->is_dragging_ = true;
        window->drag_point_.x = originalPt.x;
        window->drag_point_.y = originalPt.y;
        SetCapture(hwnd);
      }
      return 0;
    }
    
    case WM_LBUTTONUP: {
      if (window->is_dragging_) {
        window->is_dragging_ = false;
        ReleaseCapture();
      }
      return 0;
    }
    
    case WM_MOUSEMOVE: {
      if (window->is_dragging_) {
        RECT rect;
        GetWindowRect(hwnd, &rect);
        
        int mouse_x = LOWORD(lparam);
        int mouse_y = HIWORD(lparam);
        
        int new_x = rect.left + (mouse_x - window->drag_point_.x);
        int new_y = rect.top + (mouse_y - window->drag_point_.y);
        
        SetWindowPos(hwnd, HWND_TOPMOST, new_x, new_y, 0, 0,
                     SWP_NOSIZE | SWP_NOACTIVATE);
      }
      
      // Track mouse hover
      if (!window->is_hovered_) {
        window->is_hovered_ = true;
        window->hover_start_time_ = GetTickCount();
        
        OutputDebugStringW(L"[DesktopLyric] Mouse entered, starting hover timer\n");
        
        // Start tracking mouse leave
        TRACKMOUSEEVENT tme = {};
        tme.cbSize = sizeof(TRACKMOUSEEVENT);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = hwnd;
        TrackMouseEvent(&tme);
        
        // Set timer to show controls after delay
        SetTimer(hwnd, 1, kHoverDelay, nullptr);
      }
      return 0;
    }
    
    case WM_MOUSELEAVE: {
      window->is_hovered_ = false;
      window->show_controls_ = false;
      window->hover_start_time_ = 0;
      KillTimer(hwnd, 1);
      
      // Get current window position
      RECT rect;
      GetWindowRect(hwnd, &rect);
      
      // Calculate logical horizontal dimensions
      bool hasTranslation = window->show_translation_ && !window->translation_text_.empty();
      int logical_width = kWindowWidth;
      int logical_height = hasTranslation 
          ? kWindowHeight + static_cast<int>(window->font_size_ * 0.6f) + 10
          : kWindowHeight;
      
      // For vertical mode, swap dimensions
      int new_width = window->is_vertical_ ? logical_height : logical_width;
      int new_height = window->is_vertical_ ? logical_width : logical_height;
      
      // Resize window back to lyric-only size (keep position)
      SetWindowPos(hwnd, HWND_TOPMOST, rect.left, rect.top, 
                   new_width, new_height,
                   SWP_NOACTIVATE);
      window->UpdateWindow();
      return 0;
    }
    
    case WM_TIMER: {
      if (wparam == 1 && window->is_hovered_ && !window->show_controls_) {
        // Timer 1: Show control panel after hover delay
        window->show_controls_ = true;
        KillTimer(hwnd, 1);
        
        OutputDebugStringW(L"[DesktopLyric] Timer triggered, showing control panel\n");
        
        // Get current window position
        RECT rect;
        GetWindowRect(hwnd, &rect);
        
        // Calculate logical dimensions for control panel
        int logical_width = kWindowWidth;
        int logical_height = window->GetControlPanelHeight();
        
        // For vertical mode, swap dimensions
        int new_width = window->is_vertical_ ? logical_height : logical_width;
        int new_height = window->is_vertical_ ? logical_width : logical_height;
        
        // Resize window to show control panel
        SetWindowPos(hwnd, HWND_TOPMOST, rect.left, rect.top, 
                     new_width, new_height,
                     SWP_NOACTIVATE);
        window->UpdateWindow();
      } else if (wparam == 2) {
        // Timer 2: Scroll animation refresh
        if (!window->show_controls_ && (window->lyric_needs_scroll_ || window->trans_needs_scroll_)) {
          window->UpdateWindow();
        } else {
          KillTimer(hwnd, 2);
        }
      }
      return 0;
    }
    
    case WM_DESTROY: {
      PostQuitMessage(0);
      return 0;
    }
  }
  
  return DefWindowProc(hwnd, message, wparam, lparam);
}

// Helper method implementations
bool DesktopLyricWindow::IsPointInRect(const POINT& pt, const RECT& rect) const {
  return pt.x >= rect.left && pt.x <= rect.right && 
         pt.y >= rect.top && pt.y <= rect.bottom;
}

bool DesktopLyricWindow::HandleButtonClick(const POINT& pt) {
  // Debug: output button rects
  wchar_t dbg[512];
  swprintf_s(dbg, L"[DesktopLyric] HandleButtonClick pt(%d,%d), play_rect(%d,%d,%d,%d), prev_rect(%d,%d,%d,%d)\n",
             pt.x, pt.y,
             play_pause_button_rect_.left, play_pause_button_rect_.top,
             play_pause_button_rect_.right, play_pause_button_rect_.bottom,
             prev_button_rect_.left, prev_button_rect_.top,
             prev_button_rect_.right, prev_button_rect_.bottom);
  OutputDebugStringW(dbg);
  
  if (IsPointInRect(pt, prev_button_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Previous button clicked\n");
    if (playback_callback_) playback_callback_("previous");
    return true;
  } else if (IsPointInRect(pt, play_pause_button_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Play/Pause button clicked\n");
    if (playback_callback_) playback_callback_("play_pause");
    return true;
  } else if (IsPointInRect(pt, next_button_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Next button clicked\n");
    if (playback_callback_) playback_callback_("next");
    return true;
  } else if (IsPointInRect(pt, font_size_up_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Font size up clicked\n");
    if (playback_callback_) playback_callback_("font_size_up");
    return true;
  } else if (IsPointInRect(pt, font_size_down_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Font size down clicked\n");
    if (playback_callback_) playback_callback_("font_size_down");
    return true;
  } else if (IsPointInRect(pt, color_picker_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Color picker clicked\n");
    if (playback_callback_) playback_callback_("color_picker");
    return true;
  } else if (IsPointInRect(pt, translation_toggle_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Translation toggle clicked\n");
    if (playback_callback_) playback_callback_("toggle_translation");
    return true;
  } else if (IsPointInRect(pt, vertical_toggle_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Vertical toggle clicked\n");
    if (playback_callback_) playback_callback_("toggle_vertical");
    return true;
  } else if (IsPointInRect(pt, close_button_rect_)) {
    OutputDebugStringW(L"[DesktopLyric] Close button clicked\n");
    if (playback_callback_) playback_callback_("close");
    return true;
  }
  OutputDebugStringW(L"[DesktopLyric] No button matched\n");
  return false;  // No button was clicked
}

void DesktopLyricWindow::SetTranslationText(const std::wstring& text) {
  // Reset scroll state when translation changes
  if (translation_text_ != text) {
    trans_scroll_offset_ = 0.0f;
    trans_needs_scroll_ = false;
    trans_text_width_ = 0.0f;
    trans_scroll_pause_start_ = GetTickCount();
    trans_scroll_speed_ = 0.0f;  // Will be calculated in DrawLyric
  }
  translation_text_ = text;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetShowTranslation(bool show) {
  show_translation_ = show;
  if (IsVisible()) {
    UpdateWindow();
  }
}

void DesktopLyricWindow::SetVertical(bool vertical) {
  if (is_vertical_ != vertical) {
    is_vertical_ = vertical;
    
    // Update window size based on orientation (swap dimensions)
    if (hwnd_ != nullptr) {
      RECT rect;
      GetWindowRect(hwnd_, &rect);
      
      // Calculate logical horizontal dimensions
      bool hasTranslation = show_translation_ && !translation_text_.empty();
      int logical_width = kWindowWidth;
      int logical_height = hasTranslation 
          ? kWindowHeight + static_cast<int>(font_size_ * 0.6f) + 10
          : kWindowHeight;
      
      // For vertical mode, swap width and height
      int new_width = vertical ? logical_height : logical_width;
      int new_height = vertical ? logical_width : logical_height;
      
      SetWindowPos(hwnd_, HWND_TOPMOST, rect.left, rect.top, 
                   new_width, new_height, SWP_NOACTIVATE);
    }
    
    if (IsVisible()) {
      UpdateWindow();
    }
  }
}

void DesktopLyricWindow::DrawControlPanel(HDC hdc, int width, int height) {
  OutputDebugStringW(L"[DesktopLyric] Drawing control panel\n");
  
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAlias);
  
  // In vertical mode, apply 90° clockwise rotation
  // width/height params are logical (horizontal) dimensions
  // actual bitmap dimensions are swapped
  if (is_vertical_) {
    int actual_width = height;   // actual bitmap width = logical height
    int actual_height = width;   // actual bitmap height = logical width
    graphics.TranslateTransform(static_cast<Gdiplus::REAL>(actual_width) / 2.0f, 
                                 static_cast<Gdiplus::REAL>(actual_height) / 2.0f);
    graphics.RotateTransform(90.0f);
    graphics.TranslateTransform(-static_cast<Gdiplus::REAL>(actual_height) / 2.0f, 
                                 -static_cast<Gdiplus::REAL>(actual_width) / 2.0f);
  }
  
  // Draw semi-transparent background
  Gdiplus::SolidBrush bg_brush(Gdiplus::Color(200, 30, 30, 30));  // Semi-transparent dark gray
  Gdiplus::RectF bg_rect(0, 0, static_cast<Gdiplus::REAL>(width), static_cast<Gdiplus::REAL>(height));
  graphics.FillRectangle(&bg_brush, bg_rect);
  
  // Draw rounded border
  Gdiplus::Pen border_pen(Gdiplus::Color(150, 255, 255, 255), 2.0f);
  Gdiplus::GraphicsPath path;
  float radius = 10.0f;
  Gdiplus::RectF rect(1, 1, static_cast<Gdiplus::REAL>(width - 2), static_cast<Gdiplus::REAL>(height - 2));
  path.AddArc(rect.X, rect.Y, radius * 2, radius * 2, 180, 90);
  path.AddArc(rect.X + rect.Width - radius * 2, rect.Y, radius * 2, radius * 2, 270, 90);
  path.AddArc(rect.X + rect.Width - radius * 2, rect.Y + rect.Height - radius * 2, radius * 2, radius * 2, 0, 90);
  path.AddArc(rect.X, rect.Y + rect.Height - radius * 2, radius * 2, radius * 2, 90, 90);
  path.CloseFigure();
  graphics.DrawPath(&border_pen, &path);
  
  // Draw close button (top-right corner)
  int close_btn_size = 24;
  int close_x = width - close_btn_size - 10;
  int close_y = 10;
  close_button_rect_.left = close_x;
  close_button_rect_.top = close_y;
  close_button_rect_.right = close_x + close_btn_size;
  close_button_rect_.bottom = close_y + close_btn_size;
  
  Gdiplus::SolidBrush close_bg_brush(Gdiplus::Color(150, 200, 60, 60));
  graphics.FillEllipse(&close_bg_brush, static_cast<Gdiplus::REAL>(close_x), 
                       static_cast<Gdiplus::REAL>(close_y), 
                       static_cast<Gdiplus::REAL>(close_btn_size), 
                       static_cast<Gdiplus::REAL>(close_btn_size));
  // Draw X (with rotation in vertical mode)
  {
    float closeCenterX = close_x + close_btn_size / 2.0f;
    float closeCenterY = close_y + close_btn_size / 2.0f;
    Gdiplus::GraphicsState closeState = ApplyButtonRotation(graphics, is_vertical_, closeCenterX, closeCenterY);
    Gdiplus::Pen close_pen(Gdiplus::Color(255, 255, 255, 255), 2.0f);
    graphics.DrawLine(&close_pen, 
                      static_cast<Gdiplus::REAL>(close_x + 7), static_cast<Gdiplus::REAL>(close_y + 7),
                      static_cast<Gdiplus::REAL>(close_x + close_btn_size - 7), static_cast<Gdiplus::REAL>(close_y + close_btn_size - 7));
    graphics.DrawLine(&close_pen, 
                      static_cast<Gdiplus::REAL>(close_x + close_btn_size - 7), static_cast<Gdiplus::REAL>(close_y + 7),
                      static_cast<Gdiplus::REAL>(close_x + 7), static_cast<Gdiplus::REAL>(close_y + close_btn_size - 7));
    graphics.Restore(closeState);
  }
  
  // Draw song info
  Gdiplus::FontFamily fontFamily(L"Microsoft YaHei");
  Gdiplus::Font title_font(&fontFamily, 18, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::Font artist_font(&fontFamily, 14, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
  Gdiplus::SolidBrush text_brush(Gdiplus::Color(255, 255, 255, 255));
  
  // Song title
  if (!song_title_.empty()) {
    Gdiplus::RectF title_rect(20, 15, static_cast<Gdiplus::REAL>(width - 80), 25);
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    graphics.DrawString(song_title_.c_str(), -1, &title_font, title_rect, &format, &text_brush);
  }
  
  // Artist name
  if (!song_artist_.empty()) {
    Gdiplus::RectF artist_rect(20, 45, static_cast<Gdiplus::REAL>(width - 80), 20);
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    Gdiplus::SolidBrush artist_brush(Gdiplus::Color(200, 255, 255, 255));
    graphics.DrawString(song_artist_.c_str(), -1, &artist_font, artist_rect, &format, &artist_brush);
  }
  
  // Draw lyric text with original style (same as DrawLyric)
  int lyric_y = 70;
  if (!lyric_text_.empty()) {
    // Use user-configured font size and style
    Gdiplus::FontFamily lyricFontFamily(L"Microsoft YaHei");
    Gdiplus::Font lyric_font(&lyricFontFamily, static_cast<Gdiplus::REAL>(font_size_), 
                             Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    // Dynamic lyric area height based on font size
    int lyric_area_height = font_size_ + 10;
    Gdiplus::RectF lyric_rect(20, static_cast<Gdiplus::REAL>(lyric_y), static_cast<Gdiplus::REAL>(width - 40), 
                               static_cast<Gdiplus::REAL>(lyric_area_height));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    
    // Draw with stroke effect (same as original lyric)
    if (stroke_width_ > 0) {
      Gdiplus::GraphicsPath lyric_path;
      lyric_path.AddString(lyric_text_.c_str(), -1, &lyricFontFamily, 
                           Gdiplus::FontStyleBold, static_cast<Gdiplus::REAL>(font_size_),
                           lyric_rect, &format);
      
      // Stroke pen with user-configured color
      Gdiplus::Pen lyric_stroke_pen(Gdiplus::Color(
          (stroke_color_ >> 24) & 0xFF,
          (stroke_color_ >> 16) & 0xFF,
          (stroke_color_ >> 8) & 0xFF,
          stroke_color_ & 0xFF
      ), static_cast<Gdiplus::REAL>(stroke_width_));
      lyric_stroke_pen.SetLineJoin(Gdiplus::LineJoinRound);
      graphics.DrawPath(&lyric_stroke_pen, &lyric_path);
      
      // Fill text with user-configured color
      Gdiplus::SolidBrush lyric_text_brush(Gdiplus::Color(
          (text_color_ >> 24) & 0xFF,
          (text_color_ >> 16) & 0xFF,
          (text_color_ >> 8) & 0xFF,
          text_color_ & 0xFF
      ));
      graphics.FillPath(&lyric_text_brush, &lyric_path);
    } else {
      // No stroke, draw text directly with user-configured color
      Gdiplus::SolidBrush lyric_text_brush(Gdiplus::Color(
          (text_color_ >> 24) & 0xFF,
          (text_color_ >> 16) & 0xFF,
          (text_color_ >> 8) & 0xFF,
          text_color_ & 0xFF
      ));
      graphics.DrawString(lyric_text_.c_str(), -1, &lyric_font, lyric_rect, &format, &lyric_text_brush);
    }
    lyric_y += lyric_area_height;
  }
  
  // Draw translation if enabled and available
  if (show_translation_ && !translation_text_.empty()) {
    Gdiplus::Font trans_font(&fontFamily, static_cast<Gdiplus::REAL>(font_size_ * 0.7f), 
                              Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
    int trans_height = static_cast<int>(font_size_ * 0.7f) + 5;
    Gdiplus::RectF trans_rect(20, static_cast<Gdiplus::REAL>(lyric_y), 
                               static_cast<Gdiplus::REAL>(width - 40), 
                               static_cast<Gdiplus::REAL>(trans_height));
    Gdiplus::StringFormat format;
    format.SetAlignment(Gdiplus::StringAlignmentCenter);
    format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
    Gdiplus::SolidBrush trans_brush(Gdiplus::Color(180, 255, 255, 255));
    graphics.DrawString(translation_text_.c_str(), -1, &trans_font, trans_rect, &format, &trans_brush);
    lyric_y += trans_height;
  }
  
  // Draw control buttons (position based on font size)
  int button_y = lyric_y + 15;
  int button_size = 36;
  int small_btn_size = 28;
  int button_spacing = 50;
  int center_x = width / 2;
  
  Gdiplus::SolidBrush button_brush(Gdiplus::Color(180, 255, 255, 255));
  Gdiplus::SolidBrush icon_brush(Gdiplus::Color(255, 30, 30, 30));
  Gdiplus::Pen button_pen(Gdiplus::Color(255, 255, 255, 255), 2.0f);
  
  // Previous button
  int prev_x = center_x - button_spacing - button_size / 2;
  prev_button_rect_.left = prev_x;
  prev_button_rect_.top = button_y;
  prev_button_rect_.right = prev_x + button_size;
  prev_button_rect_.bottom = button_y + button_size;
  
  // Draw previous button (◀)
  graphics.FillEllipse(&button_brush, static_cast<Gdiplus::REAL>(prev_x), 
                       static_cast<Gdiplus::REAL>(button_y), 
                       static_cast<Gdiplus::REAL>(button_size), 
                       static_cast<Gdiplus::REAL>(button_size));
  {
    float prevCenterX = prev_x + button_size / 2.0f;
    float prevCenterY = button_y + button_size / 2.0f;
    Gdiplus::GraphicsState prevState = ApplyButtonRotation(graphics, is_vertical_, prevCenterX, prevCenterY);
    Gdiplus::PointF prev_triangle[3] = {
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(prev_x + button_size * 0.6f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.3f)),
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(prev_x + button_size * 0.6f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.7f)),
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(prev_x + button_size * 0.35f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.5f))
    };
    graphics.FillPolygon(&icon_brush, prev_triangle, 3);
    graphics.Restore(prevState);
  }
  
  // Play/Pause button
  int play_x = center_x - button_size / 2;
  play_pause_button_rect_.left = play_x;
  play_pause_button_rect_.top = button_y;
  play_pause_button_rect_.right = play_x + button_size;
  play_pause_button_rect_.bottom = button_y + button_size;
  
  graphics.FillEllipse(&button_brush, static_cast<Gdiplus::REAL>(play_x), 
                       static_cast<Gdiplus::REAL>(button_y), 
                       static_cast<Gdiplus::REAL>(button_size), 
                       static_cast<Gdiplus::REAL>(button_size));
  
  {
    float playCenterX = play_x + button_size / 2.0f;
    float playCenterY = button_y + button_size / 2.0f;
    Gdiplus::GraphicsState playState = ApplyButtonRotation(graphics, is_vertical_, playCenterX, playCenterY);
    
    if (is_playing_) {
      // Draw pause icon (two vertical bars ⏸)
      int bar_width = static_cast<int>(button_size * 0.12f);
      int bar_height = static_cast<int>(button_size * 0.4f);
      int bar_y_pos = button_y + static_cast<int>(button_size * 0.3f);
      int bar1_x = play_x + static_cast<int>(button_size * 0.32f);
      int bar2_x = play_x + static_cast<int>(button_size * 0.56f);
      
      Gdiplus::RectF bar1(static_cast<Gdiplus::REAL>(bar1_x), 
                          static_cast<Gdiplus::REAL>(bar_y_pos),
                          static_cast<Gdiplus::REAL>(bar_width), 
                          static_cast<Gdiplus::REAL>(bar_height));
      Gdiplus::RectF bar2(static_cast<Gdiplus::REAL>(bar2_x), 
                          static_cast<Gdiplus::REAL>(bar_y_pos),
                          static_cast<Gdiplus::REAL>(bar_width), 
                          static_cast<Gdiplus::REAL>(bar_height));
      graphics.FillRectangle(&icon_brush, bar1);
      graphics.FillRectangle(&icon_brush, bar2);
    } else {
      // Draw play triangle (▶)
      Gdiplus::PointF play_triangle[3] = {
        Gdiplus::PointF(static_cast<Gdiplus::REAL>(play_x + button_size * 0.38f), 
                        static_cast<Gdiplus::REAL>(button_y + button_size * 0.3f)),
        Gdiplus::PointF(static_cast<Gdiplus::REAL>(play_x + button_size * 0.38f), 
                        static_cast<Gdiplus::REAL>(button_y + button_size * 0.7f)),
        Gdiplus::PointF(static_cast<Gdiplus::REAL>(play_x + button_size * 0.68f), 
                        static_cast<Gdiplus::REAL>(button_y + button_size * 0.5f))
      };
      graphics.FillPolygon(&icon_brush, play_triangle, 3);
    }
    graphics.Restore(playState);
  }
  
  // Next button
  int next_x = center_x + button_spacing - button_size / 2;
  next_button_rect_.left = next_x;
  next_button_rect_.top = button_y;
  next_button_rect_.right = next_x + button_size;
  next_button_rect_.bottom = button_y + button_size;
  
  graphics.FillEllipse(&button_brush, static_cast<Gdiplus::REAL>(next_x), 
                       static_cast<Gdiplus::REAL>(button_y), 
                       static_cast<Gdiplus::REAL>(button_size), 
                       static_cast<Gdiplus::REAL>(button_size));
  // Draw next triangle (▶)
  {
    float nextCenterX = next_x + button_size / 2.0f;
    float nextCenterY = button_y + button_size / 2.0f;
    Gdiplus::GraphicsState nextState = ApplyButtonRotation(graphics, is_vertical_, nextCenterX, nextCenterY);
    Gdiplus::PointF next_triangle[3] = {
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(next_x + button_size * 0.4f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.3f)),
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(next_x + button_size * 0.4f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.7f)),
      Gdiplus::PointF(static_cast<Gdiplus::REAL>(next_x + button_size * 0.65f), 
                      static_cast<Gdiplus::REAL>(button_y + button_size * 0.5f))
    };
    graphics.FillPolygon(&icon_brush, next_triangle, 3);
    graphics.Restore(nextState);
  }
  
  // Second row of buttons (font size, color, translation toggle)
  int row2_y = button_y + button_size + 10;
  int row2_spacing = 55;
  
  // Font size down button (A-)
  int font_down_x = center_x - static_cast<int>(row2_spacing * 1.5f) - small_btn_size / 2;
  font_size_down_rect_.left = font_down_x;
  font_size_down_rect_.top = row2_y;
  font_size_down_rect_.right = font_down_x + small_btn_size;
  font_size_down_rect_.bottom = row2_y + small_btn_size;
  
  Gdiplus::SolidBrush small_btn_brush(Gdiplus::Color(150, 255, 255, 255));
  graphics.FillEllipse(&small_btn_brush, static_cast<Gdiplus::REAL>(font_down_x), 
                       static_cast<Gdiplus::REAL>(row2_y), 
                       static_cast<Gdiplus::REAL>(small_btn_size), 
                       static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::Font small_icon_font(&fontFamily, 12, Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::RectF font_down_rect_f(static_cast<Gdiplus::REAL>(font_down_x), 
                                   static_cast<Gdiplus::REAL>(row2_y), 
                                   static_cast<Gdiplus::REAL>(small_btn_size), 
                                   static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::StringFormat center_format;
  center_format.SetAlignment(Gdiplus::StringAlignmentCenter);
  center_format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  {
    float fontDownCenterX = font_down_x + small_btn_size / 2.0f;
    float fontDownCenterY = row2_y + small_btn_size / 2.0f;
    Gdiplus::GraphicsState fontDownState = ApplyButtonRotation(graphics, is_vertical_, fontDownCenterX, fontDownCenterY);
    graphics.DrawString(L"A-", -1, &small_icon_font, font_down_rect_f, &center_format, &icon_brush);
    graphics.Restore(fontDownState);
  }
  
  // Font size up button (A+)
  int font_up_x = center_x - static_cast<int>(row2_spacing * 0.5f) - small_btn_size / 2;
  font_size_up_rect_.left = font_up_x;
  font_size_up_rect_.top = row2_y;
  font_size_up_rect_.right = font_up_x + small_btn_size;
  font_size_up_rect_.bottom = row2_y + small_btn_size;
  
  graphics.FillEllipse(&small_btn_brush, static_cast<Gdiplus::REAL>(font_up_x), 
                       static_cast<Gdiplus::REAL>(row2_y), 
                       static_cast<Gdiplus::REAL>(small_btn_size), 
                       static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::RectF font_up_rect_f(static_cast<Gdiplus::REAL>(font_up_x), 
                                 static_cast<Gdiplus::REAL>(row2_y), 
                                 static_cast<Gdiplus::REAL>(small_btn_size), 
                                 static_cast<Gdiplus::REAL>(small_btn_size));
  {
    float fontUpCenterX = font_up_x + small_btn_size / 2.0f;
    float fontUpCenterY = row2_y + small_btn_size / 2.0f;
    Gdiplus::GraphicsState fontUpState = ApplyButtonRotation(graphics, is_vertical_, fontUpCenterX, fontUpCenterY);
    graphics.DrawString(L"A+", -1, &small_icon_font, font_up_rect_f, &center_format, &icon_brush);
    graphics.Restore(fontUpState);
  }
  
  // Color picker button (palette icon - using colored circle)
  int color_x = center_x + static_cast<int>(row2_spacing * 0.5f) - small_btn_size / 2;
  color_picker_rect_.left = color_x;
  color_picker_rect_.top = row2_y;
  color_picker_rect_.right = color_x + small_btn_size;
  color_picker_rect_.bottom = row2_y + small_btn_size;
  
  // Draw with current text color to show what color is selected
  Gdiplus::SolidBrush color_btn_brush(Gdiplus::Color(
      (text_color_ >> 24) & 0xFF,
      (text_color_ >> 16) & 0xFF,
      (text_color_ >> 8) & 0xFF,
      text_color_ & 0xFF
  ));
  graphics.FillEllipse(&color_btn_brush, static_cast<Gdiplus::REAL>(color_x), 
                       static_cast<Gdiplus::REAL>(row2_y), 
                       static_cast<Gdiplus::REAL>(small_btn_size), 
                       static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::Pen color_border_pen(Gdiplus::Color(255, 255, 255, 255), 2.0f);
  graphics.DrawEllipse(&color_border_pen, static_cast<Gdiplus::REAL>(color_x), 
                       static_cast<Gdiplus::REAL>(row2_y), 
                       static_cast<Gdiplus::REAL>(small_btn_size), 
                       static_cast<Gdiplus::REAL>(small_btn_size));
  
  // Translation toggle button (译)
  int trans_x = center_x + static_cast<int>(row2_spacing * 1.5f) - small_btn_size / 2;
  translation_toggle_rect_.left = trans_x;
  translation_toggle_rect_.top = row2_y;
  translation_toggle_rect_.right = trans_x + small_btn_size;
  translation_toggle_rect_.bottom = row2_y + small_btn_size;
  
  // Use different color based on translation state
  Gdiplus::SolidBrush trans_btn_brush(show_translation_ 
      ? Gdiplus::Color(200, 100, 200, 100)   // Green when enabled
      : Gdiplus::Color(150, 128, 128, 128)); // Gray when disabled
  graphics.FillEllipse(&trans_btn_brush, static_cast<Gdiplus::REAL>(trans_x), 
                       static_cast<Gdiplus::REAL>(row2_y), 
                       static_cast<Gdiplus::REAL>(small_btn_size), 
                       static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::RectF trans_rect_f(static_cast<Gdiplus::REAL>(trans_x), 
                               static_cast<Gdiplus::REAL>(row2_y), 
                               static_cast<Gdiplus::REAL>(small_btn_size), 
                               static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::SolidBrush trans_text_brush(Gdiplus::Color(255, 255, 255, 255));
  {
    float transCenterX = trans_x + small_btn_size / 2.0f;
    float transCenterY = row2_y + small_btn_size / 2.0f;
    Gdiplus::GraphicsState transState = ApplyButtonRotation(graphics, is_vertical_, transCenterX, transCenterY);
    graphics.DrawString(L"译", -1, &small_icon_font, trans_rect_f, &center_format, &trans_text_brush);
    graphics.Restore(transState);
  }
  
  // Vertical toggle button (竖/横)
  int vert_x = center_x + static_cast<int>(row2_spacing * 2.5f) - small_btn_size / 2;
  vertical_toggle_rect_.left = vert_x;
  vertical_toggle_rect_.top = row2_y;
  vertical_toggle_rect_.right = vert_x + small_btn_size;
  vertical_toggle_rect_.bottom = row2_y + small_btn_size;
  
  // Use different color based on vertical state
  Gdiplus::SolidBrush vert_btn_brush(is_vertical_ 
      ? Gdiplus::Color(200, 100, 150, 200)   // Blue when vertical
      : Gdiplus::Color(150, 128, 128, 128)); // Gray when horizontal
  graphics.FillEllipse(&vert_btn_brush, static_cast<Gdiplus::REAL>(vert_x), 
                       static_cast<Gdiplus::REAL>(row2_y), 
                       static_cast<Gdiplus::REAL>(small_btn_size), 
                       static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::RectF vert_rect_f(static_cast<Gdiplus::REAL>(vert_x), 
                              static_cast<Gdiplus::REAL>(row2_y), 
                              static_cast<Gdiplus::REAL>(small_btn_size), 
                              static_cast<Gdiplus::REAL>(small_btn_size));
  Gdiplus::SolidBrush vert_text_brush(Gdiplus::Color(255, 255, 255, 255));
  {
    float vertCenterX = vert_x + small_btn_size / 2.0f;
    float vertCenterY = row2_y + small_btn_size / 2.0f;
    Gdiplus::GraphicsState vertState = ApplyButtonRotation(graphics, is_vertical_, vertCenterX, vertCenterY);
    graphics.DrawString(is_vertical_ ? L"横" : L"竖", -1, &small_icon_font, vert_rect_f, &center_format, &vert_text_brush);
    graphics.Restore(vertState);
  }
}
