// Abre o stream de vídeo da PIXY por N segundos (padrão 5) e sai. Uso: camstream [segundos]
import AVFoundation
import Foundation

let secs = Double(CommandLine.arguments.dropFirst().first ?? "5") ?? 5
let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.externalUnknown, .builtInWideAngleCamera], mediaType: .video, position: .unspecified)
guard let dev = discovery.devices.first(where: { $0.localizedName.contains("PIXY") }) else { print("PIXY não encontrada"); exit(1) }
let session = AVCaptureSession()
session.sessionPreset = .medium
let input = try AVCaptureDeviceInput(device: dev)
session.addInput(input)
let output = AVCaptureVideoDataOutput()
session.addOutput(output)
session.startRunning()
print("stream aberto (\(dev.localizedName)), running=\(session.isRunning)")
Thread.sleep(forTimeInterval: secs)
session.stopRunning()
print("stream fechado")
