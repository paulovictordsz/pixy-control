import AVFoundation
import Foundation
import ServiceManagement
import SwiftUI

struct Preset: Codable, Equatable {
    var pan: Float
    var tilt: Float
}

/// Estado observável da câmera para a interface. Todas as chamadas são serializadas pelo transporte.
@MainActor
final class PixyController: ObservableObject {
    let transport = PixyTransport()

    @Published var connected = false
    @Published var firmware = "–"
    @Published var serial = "–"
    @Published var pan: Float = 0          // alvo (slider)
    @Published var tilt: Float = 0
    @Published var panCurrent: Float = 0   // leitura real
    @Published var tiltCurrent: Float = 0
    @Published var gestures: [Bool] = [false, false, false, false]
    @Published var flipH = false
    @Published var flipV = false
    @Published var tracking = false
    @Published var privacy = false

    /// Privacidade automática: a câmera abaixa sozinha depois de N segundos sem vídeo.
    /// O firmware guarda o valor; o app guarda a escolha para reaplicar e para mostrar "desligado".
    struct AutoPrivacyOption: Identifiable, Hashable {
        let seconds: UInt32
        let label: String
        var id: UInt32 { seconds }
    }
    static let autoPrivacyOptions: [AutoPrivacyOption] = [
        .init(seconds: 1, label: "na hora"), .init(seconds: 10, label: "10 s"), .init(seconds: 30, label: "30 s"),
        .init(seconds: 120, label: "2 min"), .init(seconds: 300, label: "5 min"),
    ]
    /// Valor enviado ao firmware para "desligado".
    static let autoPrivacyOff: UInt32 = 0
    @Published var autoPrivacy: Bool = UserDefaults.standard.bool(forKey: "pixybar.autoprivacy")
    @Published var autoPrivacySeconds: UInt32 = {
        let v = UInt32(UserDefaults.standard.integer(forKey: "pixybar.autoprivacy.seconds"))
        return autoPrivacyOptions.contains { $0.seconds == v } ? v : 60
    }()
    @Published var status = "Procurando a PIXY…"
    @Published var busy = false
    @Published var presets: [Preset?] = PixyController.loadPresets()

    /// Última escolha do usuário para o modo seguir. É reaplicada sempre que a câmera "acorda":
    /// ao conectar (abrir o app, plugar a câmera) e ao sair do modo privacidade.
    private(set) var trackingDesired: Bool = UserDefaults.standard.bool(forKey: "pixybar.tracking")

    static let panRange: ClosedRange<Float> = -150...150
    static let tiltRange: ClosedRange<Float> = -90...90
    static let stepOptions: [Float] = [2, 5, 10]
    /// Passo das setas e dos botões direcionais, em graus (configurável).
    @Published var step: Float = {
        let v = UserDefaults.standard.float(forKey: "pixybar.step")
        return stepOptions.contains(v) ? v : 5
    }() {
        didSet { UserDefaults.standard.set(step, forKey: "pixybar.step") }
    }

    /// Reaplicar o modo seguir escolhido quando a câmera acorda (configurável).
    @Published var reapplyTrackingOnWake: Bool = UserDefaults.standard.object(forKey: "pixybar.reapplyTracking") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reapplyTrackingOnWake, forKey: "pixybar.reapplyTracking") }
    }

    // MARK: abrir junto com o Mac (item de login do sistema)

    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    /// Seção de configurações aberta no painel (não persiste).
    @Published var showSettings = false

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            status = on ? "Vai abrir junto com o Mac" : "Não abre mais com o Mac"
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            status = "Login: \(error.localizedDescription)"
        }
    }

    private var usageObservation: NSKeyValueObservation?

    init() {
        transport.link.onConnection = { [weak self] on in
            Task { @MainActor in await self?.connectionChanged(on) }
        }
        if transport.isConnected { Task { await connectionChanged(true) } }
    }

    /// Qualquer comando HID reinicia o contador da privacidade automática da câmera, então o app
    /// NÃO consulta a câmera em segundo plano. Para saber que ela "acordou" (alguém abriu o vídeo),
    /// observa `isInUseByAnotherApplication` do dispositivo de captura, que é um evento do macOS.
    private func observeCameraUsage() {
        usageObservation = nil
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.externalUnknown, .builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        guard let dev = discovery.devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains("PIXY") }) else {
            // o dispositivo de vídeo pode aparecer um pouco depois do HID
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if connected, usageObservation == nil { observeCameraUsage() }
            }
            return
        }
        usageObservation = dev.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await self?.onCameraWoke()
            }
        }
    }

    /// Chamado uma vez quando outro app abre o vídeo: sincroniza o estado e reaplica o modo seguir.
    private func onCameraWoke() async {
        guard connected else { return }
        let mode = (try? await transport.deviceMode()) ?? 0
        privacy = mode == 2
        tracking = mode == 1
        await applyDesiredTracking()
        await readPositions()
    }

    private func connectionChanged(_ on: Bool) async {
        connected = on
        if on {
            status = "Conectada"
            await refresh()
            await applyDesiredTracking()
            observeCameraUsage()
        } else {
            status = "Câmera desconectada"
            usageObservation = nil
        }
    }

    private func run(_ label: String, _ body: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await body()
            status = label
        } catch {
            status = "\(label): \(error.localizedDescription)"
        }
    }

    func refresh() async {
        await run("Atualizado") {
            let fw = try await transport.firmwareVersion()
            firmware = String(format: "0x%04X", fw)
            serial = try await transport.serial()
            await readPositions()
            for i in 0..<4 { gestures[i] = (try? await transport.gesture(UInt8(i))) ?? false }
            flipH = (try? await transport.flip(1)) ?? false
            flipV = (try? await transport.flip(2)) ?? false
            let mode = (try? await transport.deviceMode()) ?? 0
            tracking = mode == 1
            privacy = mode == 2
            if let t = try? await transport.privacyTriggerSeconds() {
                // Sincroniza com o que está no firmware (pode ter sido mudado pelo EMEET STUDIO).
                autoPrivacy = t != Self.autoPrivacyOff
                if autoPrivacy { autoPrivacySeconds = t }
            }
        }
    }

    func readPositions() async {
        if let p = try? await transport.motorPosition(.pan) { pan = p.target; panCurrent = p.current }
        if let t = try? await transport.motorPosition(.tilt) { tilt = t.target; tiltCurrent = t.current }
    }

    /// Lê a posição real de novo depois que o motor teve tempo de chegar.
    private func scheduleReadback() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await readPositions()
        }
    }

    func applyPan() async {
        let v = min(max(pan, Self.panRange.lowerBound), Self.panRange.upperBound)
        await run(String(format: "Pan → %.0f°", v)) { try await transport.setMotorPosition(.pan, v) }
        scheduleReadback()
    }

    func applyTilt() async {
        let v = min(max(tilt, Self.tiltRange.lowerBound), Self.tiltRange.upperBound)
        await run(String(format: "Tilt → %.0f°", v)) { try await transport.setMotorPosition(.tilt, v) }
        scheduleReadback()
    }

    func nudge(pan dp: Float = 0, tilt dt: Float = 0) async {
        if dp != 0 { pan = min(max(pan + dp, Self.panRange.lowerBound), Self.panRange.upperBound); await applyPan() }
        if dt != 0 { tilt = min(max(tilt + dt, Self.tiltRange.lowerBound), Self.tiltRange.upperBound); await applyTilt() }
    }

    func center() async {
        pan = 0; tilt = 0
        await run("Centralizada") {
            try await transport.setMotorPosition(.pan, 0)
            try await transport.setMotorPosition(.tilt, 0)
        }
        scheduleReadback()
    }

    func goPreset(_ i: Int) async {
        guard let p = presets[i] else { return }
        pan = p.pan; tilt = p.tilt
        await run("Preset \(i + 1)") {
            try await transport.setMotorPosition(.pan, p.pan)
            try await transport.setMotorPosition(.tilt, p.tilt)
        }
        scheduleReadback()
    }

    func savePreset(_ i: Int) {
        presets[i] = Preset(pan: pan, tilt: tilt)
        Self.store(presets)
        status = "Preset \(i + 1) salvo"
    }

    func clearPreset(_ i: Int) {
        presets[i] = nil
        Self.store(presets)
    }

    func setGesture(_ i: Int, _ on: Bool) async {
        gestures[i] = on
        await run("Gesto \(i + 1) \(on ? "ligado" : "desligado")") { try await transport.setGesture(UInt8(i), on) }
    }

    func setFlipH(_ on: Bool) async {
        flipH = on
        await run("Espelho horizontal \(on ? "ligado" : "desligado")") { try await transport.setFlip(1, on) }
    }

    func setFlipV(_ on: Bool) async {
        flipV = on
        await run("Espelho vertical \(on ? "ligado" : "desligado")") { try await transport.setFlip(2, on) }
    }

    func setAutoPrivacy(enabled: Bool? = nil, seconds: UInt32? = nil) async {
        if let e = enabled { autoPrivacy = e }
        if let s = seconds { autoPrivacySeconds = s }
        UserDefaults.standard.set(autoPrivacy, forKey: "pixybar.autoprivacy")
        UserDefaults.standard.set(Int(autoPrivacySeconds), forKey: "pixybar.autoprivacy.seconds")
        let value = autoPrivacy ? autoPrivacySeconds : Self.autoPrivacyOff
        let label = autoPrivacy
            ? "Privacidade automática: \(Self.autoPrivacyOptions.first { $0.seconds == autoPrivacySeconds }?.label ?? "\(autoPrivacySeconds) s")"
            : "Privacidade automática desligada"
        await run(label) { try await transport.setPrivacyTriggerSeconds(value) }
    }

    /// Privacidade: a câmera aponta para baixo (-90°). Ao sair, o firmware volta o tilt para 0°.
    func setPrivacy(_ on: Bool) async {
        privacy = on
        await run(on ? "Privacidade ligada" : "Privacidade desligada") { try await transport.setDeviceMode(on ? 2 : 3) }
        scheduleReadback()
        if !on {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await applyDesiredTracking()
        }
    }

    func setTracking(_ on: Bool) async {
        tracking = on
        trackingDesired = on
        UserDefaults.standard.set(on, forKey: "pixybar.tracking")
        await run("Seguir \(on ? "ligado" : "desligado")") { try await transport.setTracking(on) }
    }

    /// Garante que a câmera está no modo seguir escolhido pelo usuário (se o firmware perdeu o estado).
    func applyDesiredTracking() async {
        guard connected, !privacy, reapplyTrackingOnWake else { return }
        let actual = (try? await transport.isTracking()) ?? false
        if actual != trackingDesired {
            await run(trackingDesired ? "Seguir religado" : "Seguir desligado") { try await transport.setTracking(trackingDesired) }
            tracking = trackingDesired
        }
    }

    // MARK: presets em UserDefaults

    private static let presetsKey = "pixybar.presets"

    private static func loadPresets() -> [Preset?] {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let arr = try? JSONDecoder().decode([Preset?].self, from: data), arr.count == 3 {
            return arr
        }
        return [nil, nil, nil]
    }

    private static func store(_ p: [Preset?]) {
        if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: presetsKey) }
    }
}
