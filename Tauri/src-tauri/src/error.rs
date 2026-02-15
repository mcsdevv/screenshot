use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum CaptureError {
    #[error("Screen capture failed: {0}")]
    CaptureFailed(String),

    #[error("Recording failed: {0}")]
    RecordingFailed(String),

    #[error("Recording not active")]
    RecordingNotActive,

    #[error("Storage error: {0}")]
    StorageError(String),

    #[error("OCR failed: {0}")]
    OcrFailed(String),

    #[error("Permission denied: {0}")]
    PermissionDenied(String),

    #[error("Invalid configuration: {0}")]
    InvalidConfig(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Image error: {0}")]
    Image(#[from] image::ImageError),
}

impl Serialize for CaptureError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}
