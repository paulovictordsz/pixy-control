import Foundation

/// `PixyBar --selftest`: valida a camada HID sem interface gráfica.
enum SelfTest {
    @MainActor
    static func run() async -> Int32 {
        let t = PixyTransport()
        for _ in 0..<30 where !t.isConnected { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard t.isConnected else { print("FALHA: PIXY não encontrada (conectada? EMEET STUDIO fechado?)"); return 1 }
        print("conectada, SN \(t.link.serialNumber)")
        do {
            print(String(format: "firmware 0x%04X", try await t.firmwareVersion()))
            print("serial  \(try await t.serial())")
            let p = try await t.motorPosition(.pan), ti = try await t.motorPosition(.tilt)
            print(String(format: "pan alvo %.2f atual %.2f | tilt alvo %.2f atual %.2f", p.target, p.current, ti.target, ti.current))
            print("gestos  \(try await (0..<4).asyncMap { try await t.gesture(UInt8($0)) })")
            print("flip H \(try await t.flip(1)) V \(try await t.flip(2)) | seguindo \(try await t.isTracking()) | device mode \(try await t.deviceMode())")
            if CommandLine.arguments.contains("--move") {
                print("movendo pan para \(p.target + 10) e voltando…")
                try await t.setMotorPosition(.pan, p.target + 10)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                print(String(format: "  pan agora %.2f", try await t.motorPosition(.pan).current))
                try await t.setMotorPosition(.pan, p.target)
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                print(String(format: "  pan de volta %.2f", try await t.motorPosition(.pan).current))
            }
            print("OK")
            return 0
        } catch {
            print("FALHA: \(error.localizedDescription)")
            return 2
        }
    }
}

extension Sequence {
    func asyncMap<T>(_ f: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for e in self { out.append(try await f(e)) }
        return out
    }
}
