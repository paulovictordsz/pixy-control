import Foundation

/// Protocolo "V2" da EMEET (ver PROTOCOLO.md na raiz do projeto).
/// Report de 32 bytes: [09][grupo][sub][id][idx frag][len lo][len hi][len chunk][payload até 24 bytes]
struct PixyCommand: Hashable {
    let name: String
    let head: [UInt8]          // 4 bytes, head[0] == 0x09
    let deviceType: UInt8      // 3 bits altos do byte 1 (0 = principal, 3 = gimbal)

    init(_ name: String, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8, device: UInt8 = 0) {
        self.name = name
        self.head = [0x09, (device << 5) | (b1 & 0x1F), b2, b3]
        self.deviceType = device
    }

    func matches(_ report: [UInt8]) -> Bool {
        report.count >= 8 && report[0] == 0x09 && (report[1] & 0x1F) == (head[1] & 0x1F)
            && report[2] == head[2] && report[3] == head[3]
    }

    // Identidade
    static let getVer = PixyCommand("GET_VER", 0x01, 0x00, 0x04)
    static let getSN = PixyCommand("GET_SN", 0x01, 0x00, 0x03)
    static let getDeviceMode = PixyCommand("GET_DEVICE_MODE", 0x01, 0x01, 0x01)
    static let setDeviceMode = PixyCommand("SET_DEVICE_MODE", 0x01, 0x01, 0x00)
    static let getPrivacyTrigger = PixyCommand("GET_PRIVACY_TRIGGER_TIME", 0x02, 0x01, 0x01)
    static let setPrivacyTrigger = PixyCommand("SET_PRIVACY_TRIGGER_TIME", 0x02, 0x01, 0x00)
    // Motores (device type 3)
    static let getMotorPos = PixyCommand("GET_MOTOR_POS", 0x03, 0x01, 0x01, device: 3)
    static let setMotorPos = PixyCommand("SET_MOTOR_POS", 0x03, 0x01, 0x00, device: 3)
    static let setMotorRelative = PixyCommand("SET_MOTOR_RELATIVE_POS", 0x03, 0x01, 0x19, device: 3)
    static let getMotorSpeed = PixyCommand("GET_MOTOR_SPEED", 0x03, 0x01, 0x03, device: 3)
    static let setMotorSpeed = PixyCommand("SET_MOTOR_SPEED", 0x03, 0x01, 0x02, device: 3)
    // Imagem
    static let getReverse = PixyCommand("GET_REVERSE_STA", 0x04, 0x00, 0x07)
    static let setReverse = PixyCommand("SET_REVERSE_STA", 0x04, 0x00, 0x08)
    static let getFocusMode = PixyCommand("GET_FOCUS_MODE", 0x04, 0x00, 0x02)
    // IA
    static let getTargetTrack = PixyCommand("GET_TARGET_TRACK", 0x04, 0x01, 0x01)
    static let setTargetTrack = PixyCommand("SET_TARGET_TRACK", 0x04, 0x01, 0x00)
    static let getGesture = PixyCommand("GET_GESTURE_RECOG_STA", 0x04, 0x02, 0x01)
    static let setGesture = PixyCommand("SET_GESTURE_RECOG_STA", 0x04, 0x02, 0x00)
}

enum PixyError: LocalizedError {
    case notConnected, timeout(String), writeFailed(String), badFragment

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Câmera não conectada"
        case .timeout(let n): return "Sem resposta para \(n)"
        case .writeFailed(let n): return "Falha ao enviar \(n)"
        case .badFragment: return "Resposta fragmentada fora de ordem"
        }
    }
}

enum PixyMotor: UInt8 { case pan = 1, tilt = 2 }

/// Transporte: serializa comandos, fragmenta/remonta e casa respostas. Vive no main actor,
/// porque os callbacks do IOHIDManager chegam no run loop principal.
@MainActor
final class PixyTransport {
    let link = HIDLink()
    private var pending: Pending?
    private var chain: Task<Void, Never>?

    private struct Pending {
        let cmd: PixyCommand
        var total: Int?
        var expectIdx: UInt8 = 0
        var buffer: [UInt8] = []
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    init() {
        link.onReport = { [weak self] bytes in
            Task { @MainActor in self?.handle(report: bytes) }
        }
    }

    var isConnected: Bool { link.isConnected }

    static func buildReports(head: [UInt8], payload: [UInt8]) -> [[UInt8]] {
        let total = payload.count
        if total == 0 {
            var r = [UInt8](repeating: 0, count: HIDLink.reportSize)
            r.replaceSubrange(0..<4, with: head)
            return [r]
        }
        var reports: [[UInt8]] = []
        var off = 0
        var idx: UInt8 = 0
        while off < total {
            let n = min(24, total - off)
            var r = [UInt8](repeating: 0, count: HIDLink.reportSize)
            r.replaceSubrange(0..<4, with: head)
            r[4] = idx
            r[5] = UInt8(total & 0xFF)
            r[6] = UInt8((total >> 8) & 0xFF)
            r[7] = UInt8(n)
            r.replaceSubrange(8..<(8 + n), with: payload[off..<(off + n)])
            reports.append(r)
            off += n
            idx += 1
        }
        return reports
    }

    private func handle(report r: [UInt8]) {
        guard var p = pending, p.cmd.matches(r) else { return }
        let idx = r[4], n = Int(r[7])
        if p.total == nil {
            guard idx == 0 else { return }
            p.total = Int(r[5]) | (Int(r[6]) << 8)
        } else if idx != p.expectIdx {
            pending = nil
            p.continuation.resume(throwing: PixyError.badFragment)
            return
        }
        p.buffer += r[8..<min(8 + n, r.count)]
        p.expectIdx += 1
        if p.buffer.count >= p.total! {
            pending = nil
            p.continuation.resume(returning: Array(p.buffer.prefix(p.total!)))
        } else {
            pending = p
        }
    }

    /// Envia um comando e devolve o payload da resposta. Comandos são serializados.
    func send(_ cmd: PixyCommand, _ payload: [UInt8] = [], timeout: Double = 1.0) async throws -> [UInt8] {
        let previous = chain
        let task = Task<[UInt8], Error> { @MainActor in
            await previous?.value
            return try await self.sendNow(cmd, payload, timeout: timeout)
        }
        chain = Task { _ = try? await task.value }
        return try await task.value
    }

    private func sendNow(_ cmd: PixyCommand, _ payload: [UInt8], timeout: Double) async throws -> [UInt8] {
        guard link.isConnected else { throw PixyError.notConnected }
        let reports = PixyTransport.buildReports(head: cmd.head, payload: payload)
        let result: [UInt8] = try await withCheckedThrowingContinuation { cont in
            pending = Pending(cmd: cmd, continuation: cont)
            for r in reports where !link.write(r) {
                pending = nil
                cont.resume(throwing: PixyError.writeFailed(cmd.name))
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if let p = self.pending, p.cmd == cmd {
                    self.pending = nil
                    p.continuation.resume(throwing: PixyError.timeout(cmd.name))
                }
            }
        }
        return result
    }

    // MARK: - Chamadas tipadas (layouts validados na PIXY, ver PROTOCOLO.md)

    func firmwareVersion() async throws -> UInt16 {
        let r = try await send(.getVer)
        return r.count >= 2 ? UInt16(r[0]) | (UInt16(r[1]) << 8) : 0
    }

    func serial() async throws -> String {
        let r = try await send(.getSN)
        return String(decoding: r.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Devolve (alvo, atual) em graus.
    func motorPosition(_ m: PixyMotor) async throws -> (target: Float, current: Float) {
        let r = try await send(.getMotorPos, [m.rawValue])
        guard r.count >= 9 else { return (0, 0) }
        return (Float(bitPattern: UInt32(littleEndian: r[1...4].withUnsafeBytes { $0.load(as: UInt32.self) })),
                Float(bitPattern: UInt32(littleEndian: r[5...8].withUnsafeBytes { $0.load(as: UInt32.self) })))
    }

    func setMotorPosition(_ m: PixyMotor, _ degrees: Float) async throws {
        _ = try await send(.setMotorPos, [m.rawValue] + degrees.leBytes)
    }

    func gesture(_ type: UInt8) async throws -> Bool {
        let r = try await send(.getGesture, [type]); return r.count >= 2 && r[1] != 0
    }

    func setGesture(_ type: UInt8, _ on: Bool) async throws {
        _ = try await send(.setGesture, [type, on ? 1 : 0])
    }

    func flip(_ type: UInt8) async throws -> Bool {
        let r = try await send(.getReverse, [type]); return r.count >= 2 && r[1] != 0
    }

    func setFlip(_ type: UInt8, _ on: Bool) async throws {
        _ = try await send(.setReverse, [type, on ? 1 : 0])
    }

    /// 1 = tracking (só entra via SET_TARGET_TRACK), 2 = privacidade (tilt vai a -90°), 3 = manual.
    func deviceMode() async throws -> UInt8 {
        let r = try await send(.getDeviceMode); return r.first ?? 0
    }

    func setDeviceMode(_ mode: UInt8) async throws {
        _ = try await send(.setDeviceMode, [mode])
    }

    /// Segundos sem vídeo até a câmera entrar sozinha em privacidade (u32 LE). Padrão de fábrica: 60.
    func privacyTriggerSeconds() async throws -> UInt32 {
        let r = try await send(.getPrivacyTrigger)
        guard r.count >= 4 else { return 0 }
        return UInt32(r[0]) | (UInt32(r[1]) << 8) | (UInt32(r[2]) << 16) | (UInt32(r[3]) << 24)
    }

    func setPrivacyTriggerSeconds(_ s: UInt32) async throws {
        _ = try await send(.setPrivacyTrigger, withUnsafeBytes(of: s.littleEndian) { Array($0) })
    }

    /// Estado real do seguir: a IA só roda com device mode 1. GET_TARGET_TRACK pode dizer 1
    /// com a câmera em modo manual (após ligar, por exemplo) sem nada acontecer.
    func isTracking() async throws -> Bool {
        try await deviceMode() == 1
    }

    /// Liga: device mode 1 (IA) + SET_TARGET_TRACK 1. Desliga: SET_TARGET_TRACK 0 + device mode 3 (manual).
    /// Recusado pelo firmware enquanto a câmera está em privacidade (modo 2).
    func setTracking(_ on: Bool) async throws {
        if on {
            try await setDeviceMode(1)
            _ = try await send(.setTargetTrack, [1] + [UInt8](repeating: 0, count: 12))
        } else {
            _ = try await send(.setTargetTrack, [0] + [UInt8](repeating: 0, count: 12))
            try await setDeviceMode(3)
        }
    }
}

extension Float {
    var leBytes: [UInt8] { withUnsafeBytes(of: bitPattern.littleEndian) { Array($0) } }
}
