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
    _image_path: String,
    _languages: Option<Vec<String>>,
) -> Result<Vec<TextBlock>, CaptureError> {
    // TODO: Implement via Vision framework FFI (objc2-vision)
    // 1. Load image from path as CGImage
    // 2. Create VNImageRequestHandler
    // 3. Create VNRecognizeTextRequest with accurate level
    // 4. Perform request
    // 5. Extract VNRecognizedTextObservation results
    Err(CaptureError::OcrFailed("Not yet implemented".into()))
}
