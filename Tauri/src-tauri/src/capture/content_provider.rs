use crate::capture::config::{DisplayInfo, WindowInfo};
use crate::error::CaptureError;

pub struct ContentProvider;

impl ContentProvider {
    pub fn new() -> Self {
        Self
    }

    pub async fn get_displays(&self) -> Result<Vec<DisplayInfo>, CaptureError> {
        #[cfg(target_os = "macos")]
        {
            use core_graphics::display::CGDisplay;

            let active_displays = CGDisplay::active_displays()
                .map_err(|_| CaptureError::CaptureFailed("Failed to get displays".into()))?;

            let main_id = CGDisplay::main().id;
            let displays = active_displays
                .iter()
                .map(|&id| {
                    let display = CGDisplay::new(id);
                    let pixel_w = display.pixels_wide() as u32;
                    let pixel_h = display.pixels_high() as u32;
                    let bounds = display.bounds();
                    let scale = if bounds.size.width > 0.0 {
                        pixel_w as f64 / bounds.size.width
                    } else {
                        1.0
                    };
                    DisplayInfo {
                        id,
                        width: pixel_w,
                        height: pixel_h,
                        scale_factor: scale,
                        is_primary: id == main_id,
                    }
                })
                .collect();

            Ok(displays)
        }
        #[cfg(not(target_os = "macos"))]
        {
            Ok(vec![])
        }
    }

    pub async fn get_windows(&self) -> Result<Vec<WindowInfo>, CaptureError> {
        #[cfg(target_os = "macos")]
        {
            use core_foundation::array::CFArray;
            use core_foundation::base::{CFType, TCFType};
            use core_foundation::dictionary::CFDictionary;
            use core_foundation::number::CFNumber;
            use core_foundation::string::CFString;
            use std::ffi::c_void;

            extern "C" {
                fn CGWindowListCopyWindowInfo(
                    option: u32,
                    relative_to_window: u32,
                ) -> core_foundation::base::CFTypeRef;
            }

            // kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements
            let options: u32 = (1 << 0) | (1 << 4);

            let cf_ref = unsafe { CGWindowListCopyWindowInfo(options, 0) };
            if cf_ref.is_null() {
                return Ok(vec![]);
            }

            let array: CFArray<CFType> = unsafe { CFArray::wrap_under_create_rule(cf_ref as _) };
            let mut windows = Vec::new();

            let k_number = CFString::new("kCGWindowNumber");
            let k_name = CFString::new("kCGWindowName");
            let k_owner = CFString::new("kCGWindowOwnerName");
            let k_bounds = CFString::new("kCGWindowBounds");
            let k_layer = CFString::new("kCGWindowLayer");

            for i in 0..array.len() {
                let item = array.get(i as _).unwrap();
                let dict_ref = item.as_CFTypeRef();
                let dict: CFDictionary<CFString, CFType> = unsafe {
                    CFDictionary::wrap_under_get_rule(dict_ref as _)
                };

                // Skip non-layer-0 windows (menus, tooltips, etc.)
                if let Some(layer_val) = dict.find(&k_layer) {
                    let layer_ref = layer_val.as_CFTypeRef() as *const c_void;
                    let layer: CFNumber = unsafe { CFNumber::wrap_under_get_rule(layer_ref as _) };
                    if let Some(l) = layer.to_i32() {
                        if l != 0 { continue; }
                    }
                }

                // Get window ID
                let window_id = match dict.find(&k_number) {
                    Some(v) => {
                        let num_ref = v.as_CFTypeRef() as *const c_void;
                        let num: CFNumber = unsafe { CFNumber::wrap_under_get_rule(num_ref as _) };
                        num.to_i32().unwrap_or(0) as u32
                    }
                    None => continue,
                };

                // Get window name (skip unnamed windows)
                let title = match dict.find(&k_name) {
                    Some(v) => {
                        let str_ref = v.as_CFTypeRef() as *const c_void;
                        let s: CFString = unsafe { CFString::wrap_under_get_rule(str_ref as _) };
                        s.to_string()
                    }
                    None => continue,
                };
                if title.is_empty() { continue; }

                // Get owner name
                let app_name = match dict.find(&k_owner) {
                    Some(v) => {
                        let str_ref = v.as_CFTypeRef() as *const c_void;
                        let s: CFString = unsafe { CFString::wrap_under_get_rule(str_ref as _) };
                        s.to_string()
                    }
                    None => String::new(),
                };

                // Skip our own app
                if app_name == "ScreenCapture" { continue; }

                // Get bounds
                let (width, height) = match dict.find(&k_bounds) {
                    Some(v) => {
                        let bounds_ref = v.as_CFTypeRef();
                        let bounds_dict: CFDictionary<CFString, CFType> = unsafe {
                            CFDictionary::wrap_under_get_rule(bounds_ref as _)
                        };
                        let w_key = CFString::new("Width");
                        let h_key = CFString::new("Height");
                        let w = bounds_dict.find(&w_key)
                            .map(|n| {
                                let r = n.as_CFTypeRef() as *const c_void;
                                unsafe { CFNumber::wrap_under_get_rule(r as _) }.to_f64().unwrap_or(0.0)
                            })
                            .unwrap_or(0.0);
                        let h = bounds_dict.find(&h_key)
                            .map(|n| {
                                let r = n.as_CFTypeRef() as *const c_void;
                                unsafe { CFNumber::wrap_under_get_rule(r as _) }.to_f64().unwrap_or(0.0)
                            })
                            .unwrap_or(0.0);
                        (w as u32, h as u32)
                    }
                    None => (0, 0),
                };

                // Skip tiny windows
                if width < 50 || height < 50 { continue; }

                windows.push(WindowInfo {
                    id: window_id,
                    title,
                    app_name,
                    width,
                    height,
                });
            }

            Ok(windows)
        }
        #[cfg(not(target_os = "macos"))]
        {
            Ok(vec![])
        }
    }
}
