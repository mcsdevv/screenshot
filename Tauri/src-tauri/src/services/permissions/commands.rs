use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionStatus {
    Authorized,
    Denied,
    Restricted,
    NotDetermined,
}

#[cfg(target_os = "macos")]
extern "C" {
    fn CGPreflightScreenCaptureAccess() -> bool;
}

#[tauri::command]
pub fn check_screen_recording_permission() -> PermissionStatus {
    #[cfg(target_os = "macos")]
    {
        unsafe {
            if CGPreflightScreenCaptureAccess() {
                PermissionStatus::Authorized
            } else {
                PermissionStatus::Denied
            }
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        PermissionStatus::Authorized
    }
}

#[tauri::command]
pub fn check_microphone_permission() -> PermissionStatus {
    #[cfg(target_os = "macos")]
    {
        use objc::runtime::Class;
        use objc::{msg_send, sel, sel_impl};

        unsafe {
            let cls = match Class::get("AVCaptureDevice") {
                Some(c) => c,
                None => return PermissionStatus::NotDetermined,
            };
            // AVMediaTypeAudio = "soun"
            let ns_string_cls = Class::get("NSString").unwrap();
            let audio_type: *mut objc::runtime::Object =
                msg_send![ns_string_cls, stringWithUTF8String: b"soun\0".as_ptr()];
            let status: i64 = msg_send![cls, authorizationStatusForMediaType: audio_type];
            match status {
                0 => PermissionStatus::NotDetermined,
                1 => PermissionStatus::Restricted,
                2 => PermissionStatus::Denied,
                3 => PermissionStatus::Authorized,
                _ => PermissionStatus::NotDetermined,
            }
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        PermissionStatus::Authorized
    }
}
