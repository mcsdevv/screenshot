use crate::capture::config::{CaptureRect, ImageFormat};
use crate::error::CaptureError;

#[cfg(target_os = "macos")]
use core_graphics::display::CGDisplay;

#[cfg(target_os = "macos")]
extern "C" {
    fn CGDisplayCreateImage(display_id: u32) -> *mut core_graphics::sys::CGImage;
    fn CGDisplayCreateImageForRect(
        display_id: u32,
        rect: core_graphics::geometry::CGRect,
    ) -> *mut core_graphics::sys::CGImage;
    fn CGWindowListCreateImage(
        screen_bounds: core_graphics::geometry::CGRect,
        list_option: u32,
        window_id: u32,
        image_option: u32,
    ) -> *mut core_graphics::sys::CGImage;
    // CGImage C API functions
    fn CGImageGetWidth(image: *const core_graphics::sys::CGImage) -> usize;
    fn CGImageGetHeight(image: *const core_graphics::sys::CGImage) -> usize;
    fn CGImageGetBytesPerRow(image: *const core_graphics::sys::CGImage) -> usize;
    fn CGImageGetBitsPerPixel(image: *const core_graphics::sys::CGImage) -> usize;
    fn CGImageGetBitmapInfo(image: *const core_graphics::sys::CGImage) -> u32;
    fn CGImageGetDataProvider(
        image: *const core_graphics::sys::CGImage,
    ) -> core_foundation::base::CFTypeRef;
    fn CGDataProviderCopyData(
        provider: core_foundation::base::CFTypeRef,
    ) -> core_foundation::base::CFTypeRef;
}

pub async fn capture_fullscreen(
    display_id: Option<u32>,
    _include_cursor: bool,
    format: &ImageFormat,
) -> Result<Vec<u8>, CaptureError> {
    #[cfg(target_os = "macos")]
    {
        let id = display_id.unwrap_or_else(|| CGDisplay::main().id);
        let cg_image_ref = unsafe { CGDisplayCreateImage(id) };
        if cg_image_ref.is_null() {
            return Err(CaptureError::CaptureFailed("CGDisplayCreateImage returned null".into()));
        }
        let result = encode_cgimage_raw(cg_image_ref as _, format);
        unsafe { core_foundation::base::CFRelease(cg_image_ref as _); }
        result
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err(CaptureError::CaptureFailed("Not supported on this platform".into()))
    }
}

pub async fn capture_area(
    rect: &CaptureRect,
    display_id: u32,
    _include_cursor: bool,
    format: &ImageFormat,
) -> Result<Vec<u8>, CaptureError> {
    #[cfg(target_os = "macos")]
    {
        use core_graphics::geometry::{CGPoint, CGSize, CGRect};

        let cg_rect = CGRect::new(
            &CGPoint::new(rect.x, rect.y),
            &CGSize::new(rect.width, rect.height),
        );
        let cg_image_ref = unsafe { CGDisplayCreateImageForRect(display_id, cg_rect) };
        if cg_image_ref.is_null() {
            return Err(CaptureError::CaptureFailed("CGDisplayCreateImageForRect returned null".into()));
        }
        let result = encode_cgimage_raw(cg_image_ref as _, format);
        unsafe { core_foundation::base::CFRelease(cg_image_ref as _); }
        result
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err(CaptureError::CaptureFailed("Not supported on this platform".into()))
    }
}

pub async fn capture_window(
    window_id: u32,
    _include_cursor: bool,
    format: &ImageFormat,
) -> Result<Vec<u8>, CaptureError> {
    #[cfg(target_os = "macos")]
    {
        use core_graphics::geometry::{CGPoint, CGSize, CGRect};

        // CGRectNull = {{inf, inf}, {0, 0}} — tells CGWindowListCreateImage to use the window's bounds
        let null_rect = CGRect::new(&CGPoint::new(f64::INFINITY, f64::INFINITY), &CGSize::new(0.0, 0.0));
        // kCGWindowListOptionIncludingWindow = 1 << 3
        let list_option: u32 = 1 << 3;
        // kCGWindowImageDefault = 0
        let image_option: u32 = 0;

        let cg_image_ref = unsafe {
            CGWindowListCreateImage(null_rect, list_option, window_id, image_option)
        };
        if cg_image_ref.is_null() {
            return Err(CaptureError::CaptureFailed("CGWindowListCreateImage returned null".into()));
        }
        let result = encode_cgimage_raw(cg_image_ref as _, format);
        unsafe { core_foundation::base::CFRelease(cg_image_ref as _); }
        result
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err(CaptureError::CaptureFailed("Not supported on this platform".into()))
    }
}

#[cfg(target_os = "macos")]
fn encode_cgimage_raw(
    cg_image: *const core_graphics::sys::CGImage,
    format: &ImageFormat,
) -> Result<Vec<u8>, CaptureError> {
    use image::{DynamicImage, RgbaImage};

    let width = unsafe { CGImageGetWidth(cg_image) };
    let height = unsafe { CGImageGetHeight(cg_image) };
    let bytes_per_row = unsafe { CGImageGetBytesPerRow(cg_image) };
    let bits_per_pixel = unsafe { CGImageGetBitsPerPixel(cg_image) };
    let bitmap_info = unsafe { CGImageGetBitmapInfo(cg_image) };

    if width == 0 || height == 0 {
        return Err(CaptureError::CaptureFailed("Empty image".into()));
    }

    // Get pixel data via data provider
    let data_provider = unsafe { CGImageGetDataProvider(cg_image) };
    if data_provider.is_null() {
        return Err(CaptureError::CaptureFailed("No data provider".into()));
    }
    let cf_data = unsafe { CGDataProviderCopyData(data_provider) };
    if cf_data.is_null() {
        return Err(CaptureError::CaptureFailed("Failed to copy data".into()));
    }

    // Wrap CFData and keep it alive for the duration of pixel processing
    use core_foundation::base::TCFType;
    use core_foundation::data::CFData;
    let cf_data_obj = unsafe { CFData::wrap_under_create_rule(cf_data as _) };
    let pixel_data: &[u8] = cf_data_obj.bytes();

    // Determine pixel format from bitmap info
    // kCGBitmapByteOrder32Little = 0x2000
    let byte_order = bitmap_info & 0x7000;
    let alpha_info = bitmap_info & 0x1F;
    let is_bgra = byte_order == 0x2000 || (bits_per_pixel == 32 && alpha_info != 0);

    let mut rgba = Vec::with_capacity(width * height * 4);
    let bytes_per_pixel = bits_per_pixel / 8;
    for y in 0..height {
        let row_start = y * bytes_per_row;
        for x in 0..width {
            let px_offset = row_start + x * bytes_per_pixel;
            if px_offset + 3 < pixel_data.len() {
                if is_bgra {
                    rgba.push(pixel_data[px_offset + 2]); // R
                    rgba.push(pixel_data[px_offset + 1]); // G
                    rgba.push(pixel_data[px_offset]);     // B
                    rgba.push(pixel_data[px_offset + 3]); // A
                } else {
                    rgba.push(pixel_data[px_offset]);     // R
                    rgba.push(pixel_data[px_offset + 1]); // G
                    rgba.push(pixel_data[px_offset + 2]); // B
                    rgba.push(pixel_data[px_offset + 3]); // A
                }
            }
        }
    }

    let img = RgbaImage::from_raw(width as u32, height as u32, rgba)
        .ok_or_else(|| CaptureError::CaptureFailed("Pixel buffer size mismatch".into()))?;
    let dynamic = DynamicImage::ImageRgba8(img);

    let mut buf = Vec::new();
    let mut cursor = std::io::Cursor::new(&mut buf);
    match format {
        ImageFormat::Png => {
            dynamic.write_to(&mut cursor, image::ImageFormat::Png)?;
        }
        ImageFormat::Jpeg { quality } => {
            let q = (*quality * 100.0) as u8;
            let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut cursor, q);
            dynamic.write_with_encoder(encoder)?;
        }
        ImageFormat::Tiff => {
            dynamic.write_to(&mut cursor, image::ImageFormat::Tiff)?;
        }
    }
    Ok(buf)
}
