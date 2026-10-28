import AVFoundation
import SwiftUI

/// Preview da PIXY via AVFoundation. Só roda enquanto o painel está aberto.
@MainActor
final class CameraFeed: ObservableObject {
    let session = AVCaptureSession()
    @Published var available = false
    @Published var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published var running = false
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "pixybar.preview") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "pixybar.preview")
            enabled ? start() : stop()
        }
    }
    private var configured = false
    private let queue = DispatchQueue(label: "pixybar.camera")

    /// Uma única view de preview, criada uma vez e ligada à sessão ANTES de ela rodar.
    /// Reutilizada ao esconder/mostrar: uma layer anexada a uma sessão já em andamento fica preta no macOS.
    lazy var previewView: CameraPreview.PreviewView = {
        let v = CameraPreview.PreviewView()
        v.previewLayer.session = session
        return v
    }()

    private func configure() -> Bool {
        if configured { return available }
        configured = true
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.externalUnknown, .builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        guard let device = discovery.devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains("PIXY") })
            ?? discovery.devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains("EMEET") }),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .medium
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        available = true
        return true
    }

    func start() {
        guard enabled else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                Task { @MainActor in
                    self.authorized = ok
                    if ok { self.start() }
                }
            }
            return
        default:
            authorized = false
            return
        }
        guard configure() else { return }
        _ = previewView
        let s = session
        queue.async {
            if !s.isRunning { s.startRunning() }
            Task { @MainActor in self.running = s.isRunning }
        }
    }

    func stop() {
        let s = session
        queue.async {
            if s.isRunning { s.stopRunning() }
            Task { @MainActor in self.running = false }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let view: PreviewView

    func makeNSView(context: Context) -> PreviewView {
        view.previewLayer.connection?.isEnabled = true
        return view
    }

    func updateNSView(_ v: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.backgroundColor = NSColor.black.cgColor
            layer = previewLayer
        }

        required init?(coder: NSCoder) { fatalError() }
    }
}
