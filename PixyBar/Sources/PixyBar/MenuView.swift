import SwiftUI

struct MenuView: View {
    @EnvironmentObject var cam: PixyController
    @EnvironmentObject var feed: CameraFeed

    private let corner: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            preview
            Group {
                Divider()
                motors
                Divider()
                presets
                Divider()
                toggles
            }
            .disabled(!cam.connected)
            if cam.showSettings {
                Divider()
                settings
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
        .background(VisualEffectView(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 1))
        .padding(1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(cam.connected ? Color.green : Color.red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text("EMEET PIXY").font(.headline)
                Text("fw \(cam.firmware) · SN \(cam.serial)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if cam.busy { ProgressView().controlSize(.small) }
            Button {
                feed.enabled.toggle()
            } label: {
                Image(systemName: feed.enabled ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .help(feed.enabled ? "Esconder o visualizador" : "Mostrar o visualizador")
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { cam.showSettings.toggle() }
            } label: {
                Image(systemName: "gearshape").foregroundStyle(cam.showSettings ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.borderless)
            .help("Configurações do app")
        }
    }

    @ViewBuilder private var preview: some View {
        if feed.enabled {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black)
                CameraPreview(view: feed.previewView)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !feed.running {
                    VStack(spacing: 4) {
                        Image(systemName: feed.authorized ? "video" : "video.slash").font(.title2)
                        Text(feed.authorized ? (cam.connected ? "Abrindo a câmera…" : "Câmera desconectada")
                                             : "Sem permissão de câmera (Ajustes › Privacidade › Câmera)")
                            .font(.caption).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(8)
                }
            }
            .frame(height: 168)
            .overlay(alignment: .bottomTrailing) {
                if cam.tracking {
                    Label("seguindo", systemImage: "scope").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule()).padding(6)
                }
            }
        }
    }

    private var motors: some View {
        VStack(alignment: .leading, spacing: 8) {
            axis("Pan", value: $cam.pan, current: cam.panCurrent, range: PixyController.panRange) { Task { await cam.applyPan() } }
            axis("Tilt", value: $cam.tilt, current: cam.tiltCurrent, range: PixyController.tiltRange) { Task { await cam.applyTilt() } }
            HStack(spacing: 6) {
                Spacer()
                pad("arrow.left") { await cam.nudge(pan: -cam.step) }
                VStack(spacing: 6) {
                    pad("arrow.up") { await cam.nudge(tilt: cam.step) }
                    pad("scope") { await cam.center() }
                    pad("arrow.down") { await cam.nudge(tilt: -cam.step) }
                }
                pad("arrow.right") { await cam.nudge(pan: cam.step) }
                Spacer()
            }
            Text(String(format: "Setas movem %.0f°, 0 centraliza", cam.step)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func axis(_ label: String, value: Binding<Float>, current: Float, range: ClosedRange<Float>, apply: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.subheadline).frame(width: 34, alignment: .leading)
                Slider(value: value, in: range, onEditingChanged: { editing in if !editing { apply() } })
                Text(String(format: "%.0f°", value.wrappedValue)).font(.system(.caption, design: .monospaced)).frame(width: 42, alignment: .trailing)
            }
            HStack {
                Spacer()
                Text(String(format: "atual %.1f°", current)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func pad(_ symbol: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol).frame(width: 22, height: 18)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Presets").font(.subheadline)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    let p = cam.presets[i]
                    Button {
                        Task { await cam.goPreset(i) }
                    } label: {
                        VStack(spacing: 1) {
                            Text("\(i + 1)").font(.headline)
                            Text(p.map { String(format: "%.0f° / %.0f°", $0.pan, $0.tilt) } ?? "vazio")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(p == nil)
                    .contextMenu {
                        Button("Salvar posição atual aqui") { cam.savePreset(i) }
                        if p != nil { Button("Limpar") { cam.clearPreset(i) } }
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Button("Salvar \(i + 1)") { cam.savePreset(i) }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("Teclas 1-3 vão ao preset, ⌘1-3 salvam").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Seguir (tracking)", isOn: Binding(get: { cam.tracking }, set: { v in Task { await cam.setTracking(v) } }))
            Text(cam.tracking ? "Lembrado: a câmera acorda seguindo." : "Lembrado: a câmera acorda sem seguir.")
                .font(.caption2).foregroundStyle(.secondary)
            Toggle("Privacidade (câmera para baixo)", isOn: Binding(get: { cam.privacy }, set: { v in Task { await cam.setPrivacy(v) } }))
            HStack {
                Toggle("Privacidade automática", isOn: Binding(get: { cam.autoPrivacy }, set: { v in Task { await cam.setAutoPrivacy(enabled: v) } }))
                Spacer()
                Picker("", selection: Binding(get: { cam.autoPrivacySeconds }, set: { v in Task { await cam.setAutoPrivacy(seconds: v) } })) {
                    ForEach(PixyController.autoPrivacyOptions) { o in Text(o.label).tag(o.seconds) }
                }
                .labelsHidden()
                .frame(width: 92)
                .disabled(!cam.autoPrivacy)
            }
            Text("Com vídeo aberto e ninguém na frente por esse tempo, a câmera abaixa sozinha.").font(.caption2).foregroundStyle(.secondary)
            Toggle("Espelhar horizontal", isOn: Binding(get: { cam.flipH }, set: { v in Task { await cam.setFlipH(v) } }))
            Toggle("Espelhar vertical", isOn: Binding(get: { cam.flipV }, set: { v in Task { await cam.setFlipV(v) } }))
            HStack {
                Text("Gestos").font(.subheadline)
                Spacer()
                ForEach(0..<4, id: \.self) { i in
                    Toggle("\(i + 1)", isOn: Binding(get: { cam.gestures[i] }, set: { v in Task { await cam.setGesture(i, v) } }))
                        .toggleStyle(.button)
                }
            }
            Text("t seguir · p privacidade · Esc fecha").font(.caption2).foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configurações").font(.subheadline)
            Toggle("Abrir junto com o Mac", isOn: Binding(get: { cam.launchAtLogin }, set: { cam.setLaunchAtLogin($0) }))
            Toggle("Mostrar o vídeo ao abrir o painel", isOn: $feed.enabled)
            Toggle("Reaplicar o seguir quando a câmera acorda", isOn: $cam.reapplyTrackingOnWake)
            HStack {
                Text("Passo das setas")
                Spacer()
                Picker("", selection: $cam.step) {
                    ForEach(PixyController.stepOptions, id: \.self) { Text(String(format: "%.0f°", $0)).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            HStack {
                Text("PixyBar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · controle local da EMEET PIXY")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Mostrar no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .font(.caption2).buttonStyle(.link)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var footer: some View {
        HStack {
            Text(cam.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button { Task { await cam.refresh() } } label: { Image(systemName: "arrow.clockwise") }
            Button("Sair") { NSApp.terminate(nil) }
        }
    }
}
