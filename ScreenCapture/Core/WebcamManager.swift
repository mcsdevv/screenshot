import AppKit
import AVFoundation
import SwiftUI

@MainActor
class WebcamManager: NSObject, ObservableObject {
    @Published var isWebcamVisible = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var captureSession: AVCaptureSession?
    private var videoDevice: AVCaptureDevice?
    private var webcamWindow: NSWindow?
    
    override init() {
        super.init()
    }
    
    func toggleWebcam() {
        if isWebcamVisible {
            hideWebcam()
        } else {
            showWebcam()
        }
    }
    
    func showWebcam() {
        requestCameraPermission { [weak self] granted in
            guard granted else {
                return
            }
            
            Task { @MainActor in
                self?.setupCaptureSession()
                self?.createWebcamWindow()
                self?.isWebcamVisible = true
            }
        }
    }
    
    func hideWebcam() {
        captureSession?.stopRunning()
        webcamWindow?.orderOut(nil)
        webcamWindow?.close()
        webcamWindow = nil
        previewLayer = nil
        isWebcamVisible = false
    }
    
    private func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return
        }
        
        self.videoDevice = videoDevice
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            self.previewLayer = preview
            
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
            
            self.captureSession = session
        } catch {}
    }
    
    private func createWebcamWindow() {
        guard let previewLayer = previewLayer else {
            return
        }
        
        let webcamView = WebcamOverlayView(previewLayer: previewLayer)
        let hostingView = NSHostingView(rootView: webcamView)
        
        let size: CGFloat = 200
        hostingView.frame = NSRect(x: 0, y: 0, width: size, height: size)
        
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 20
        
        let windowFrame = NSRect(
            x: screenFrame.maxX - size - padding,
            y: screenFrame.minY + padding,
            width: size,
            height: size
        )
        
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        
        webcamWindow = window
        window.orderFrontRegardless()
    }
}

// MARK: - Webcam Overlay View

struct WebcamOverlayView: View {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    var body: some View {
        VideoPreviewView(previewLayer: previewLayer)
            .frame(width: 200, height: 200)
            .scaleEffect(x: -1, y: 1)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

// MARK: - Video Preview NSView Wrapper

struct VideoPreviewView: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        previewLayer.frame = view.bounds
        view.layer?.addSublayer(previewLayer)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            previewLayer.frame = nsView.bounds
        }
    }
}
