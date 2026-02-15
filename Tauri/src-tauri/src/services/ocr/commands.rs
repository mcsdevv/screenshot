use serde::{Deserialize, Serialize};
use crate::error::CaptureError;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextBlock {
    pub text: String,
    pub confidence: f32,
    pub bounding_box: BoundingBox,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoundingBox {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[tauri::command]
pub async fn recognize_text(
    image_path: String,
    _languages: Option<Vec<String>>,
) -> Result<Vec<TextBlock>, CaptureError> {
    #[cfg(target_os = "macos")]
    {
        use objc::runtime::{Class, Object};
        use objc::{msg_send, sel, sel_impl};
        use std::ffi::CString;

        tokio::task::spawn_blocking(move || {
            // Create autorelease pool for ObjC objects on this background thread
            let pool: *mut Object = unsafe { msg_send![Class::get("NSAutoreleasePool").unwrap(), new] };

            let result = unsafe {
                // Load image as NSImage
                let path_c = CString::new(image_path.as_bytes())
                    .map_err(|_| CaptureError::OcrFailed("Invalid path".into()))?;
                let ns_string_cls = Class::get("NSString").unwrap();
                let ns_path: *mut Object = msg_send![ns_string_cls, stringWithUTF8String: path_c.as_ptr()];

                let ns_image_cls = Class::get("NSImage").unwrap();
                let ns_image: *mut Object = msg_send![ns_image_cls, alloc];
                let ns_image: *mut Object = msg_send![ns_image, initWithContentsOfFile: ns_path];
                if ns_image.is_null() {
                    return Err(CaptureError::OcrFailed("Failed to load image".into()));
                }

                // Get CGImage from NSImage
                let null_ptr: *mut Object = std::ptr::null_mut();
                let cg_image: *mut Object = msg_send![ns_image, CGImageForProposedRect: null_ptr context: null_ptr hints: null_ptr];
                if cg_image.is_null() {
                    let _: () = msg_send![ns_image, release];
                    return Err(CaptureError::OcrFailed("Failed to get CGImage".into()));
                }

                // Create VNImageRequestHandler with empty options dict
                let handler_cls = Class::get("VNImageRequestHandler")
                    .ok_or_else(|| CaptureError::OcrFailed("Vision framework not available".into()))?;
                let dict_cls = Class::get("NSDictionary").unwrap();
                let empty_dict: *mut Object = msg_send![dict_cls, dictionary];
                let handler: *mut Object = msg_send![handler_cls, alloc];
                let handler: *mut Object = msg_send![handler, initWithCGImage: cg_image options: empty_dict];
                if handler.is_null() {
                    let _: () = msg_send![ns_image, release];
                    return Err(CaptureError::OcrFailed("Failed to create VNImageRequestHandler".into()));
                }

                // Create VNRecognizeTextRequest
                let request_cls = Class::get("VNRecognizeTextRequest").unwrap();
                let request: *mut Object = msg_send![request_cls, alloc];
                let request: *mut Object = msg_send![request, init];
                // VNRequestTextRecognitionLevelAccurate = 1
                let _: () = msg_send![request, setRecognitionLevel: 1i64];
                let _: () = msg_send![request, setUsesLanguageCorrection: true];

                // Perform request
                let ns_array_cls = Class::get("NSArray").unwrap();
                let requests: *mut Object = msg_send![ns_array_cls, arrayWithObject: request];
                let mut error: *mut Object = std::ptr::null_mut();
                let success: bool = msg_send![handler, performRequests: requests error: &mut error];
                if !success {
                    let _: () = msg_send![request, release];
                    let _: () = msg_send![handler, release];
                    let _: () = msg_send![ns_image, release];
                    return Err(CaptureError::OcrFailed("Vision request failed".into()));
                }

                // Extract results
                let results: *mut Object = msg_send![request, results];
                let mut blocks = Vec::new();

                if !results.is_null() {
                    let count: usize = msg_send![results, count];

                    for i in 0..count {
                        let observation: *mut Object = msg_send![results, objectAtIndex: i];
                        let candidates: *mut Object = msg_send![observation, topCandidates: 1usize];
                        let cand_count: usize = msg_send![candidates, count];
                        if cand_count == 0 { continue; }

                        let candidate: *mut Object = msg_send![candidates, objectAtIndex: 0usize];
                        let text_ns: *mut Object = msg_send![candidate, string];
                        let confidence: f32 = msg_send![candidate, confidence];

                        let utf8: *const i8 = msg_send![text_ns, UTF8String];
                        let text = if utf8.is_null() {
                            String::new()
                        } else {
                            std::ffi::CStr::from_ptr(utf8).to_string_lossy().to_string()
                        };

                        let bbox: core_graphics::geometry::CGRect = msg_send![observation, boundingBox];

                        blocks.push(TextBlock {
                            text,
                            confidence,
                            bounding_box: BoundingBox {
                                x: bbox.origin.x,
                                y: bbox.origin.y,
                                width: bbox.size.width,
                                height: bbox.size.height,
                            },
                        });
                    }
                }

                // Release ObjC objects
                let _: () = msg_send![request, release];
                let _: () = msg_send![handler, release];
                let _: () = msg_send![ns_image, release];

                Ok(blocks)
            };

            // Drain autorelease pool
            unsafe { let _: () = msg_send![pool, drain]; }
            result
        }).await.map_err(|e| CaptureError::OcrFailed(e.to_string()))?
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err(CaptureError::OcrFailed("OCR not supported on this platform".into()))
    }
}
