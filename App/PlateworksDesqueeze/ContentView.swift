import AppKit
import DesqueezeCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.exiftool == nil { missingExiftool }
            dropZone
            factorRow
            actionRow
            if let progress = model.progress, model.isRunning {
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                Text(progress.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let summary = model.summary { result(summary) }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            // AppKit gives the custom field the keyboard focus when the window
            // opens. Its focus ring then reads as a second selected factor.
            DispatchQueue.main.async {
                NSApp.windows.first(where: { $0.isVisible })?.makeFirstResponder(nil)
            }
        }
    }

    // MARK: Parts

    private var missingExiftool: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Desqueeze needs exiftool, and it is not installed.")
                .font(.callout.weight(.medium))
            Text("Install it in Terminal, then open Desqueeze again:")
                .font(.callout)
            Text("brew install exiftool")
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.title)
                .foregroundStyle(.secondary)
            if let name = model.folderName {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let counts = model.countsLine {
                Text(counts)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let message = model.folderMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Button("Choose folder") { model.chooseFolder() }
                .disabled(model.isRunning)
            Text("or drag a folder here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls)
        } isTargeted: {
            isTargeted = $0
        }
    }

    private var factorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Squeeze factor")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(SqueezeFactor.presets, id: \.self) { preset in
                    presetButton(preset)
                }
                TextField("1.6", text: $model.customText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .overlay {
                        if model.choice == .custom {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .onChange(of: model.customText) {
                        model.choice = .custom
                        model.customError = nil
                    }
                    .accessibilityLabel("Custom factor")
            }
            .disabled(model.isRunning)
            if let error = model.customError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func presetButton(_ preset: SqueezeFactor) -> some View {
        let select = {
            model.choice = .preset(preset)
            model.customError = nil
        }
        if model.choice == .preset(preset) {
            Button(action: select) { Text(preset.label).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action: select) { Text(preset.label).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if model.isRunning {
                Button(action: model.cancel) { Text("Cancel").frame(maxWidth: .infinity) }
                    .controlSize(.large)
            } else {
                Button(action: model.run) {
                    Text("Desqueeze \(model.runCount) photos").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRun)
            }
            Button("Remove", action: model.remove)
                .controlSize(.large)
                .disabled(!model.canRun)
                .help("Set every DNG back to no stretch")
        }
    }

    private func result(_ summary: RunSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(countsText(summary))
                .font(.callout.weight(.medium))
                .foregroundStyle(summary.failed == 0 ? Color.green : Color.red)
            Text("Photos already in Lightroom: Metadata › Read Metadata from File.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !summary.notes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.notes) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.name).font(.callout.weight(.medium))
                                Text(note.message).font(.callout)
                                if let detail = note.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    private func countsText(_ summary: RunSummary) -> String {
        var parts: [String] = []
        if summary.converted > 0 { parts.append("\(summary.converted) converted") }
        parts.append("\(summary.set) set")
        parts.append("\(summary.skipped) skipped")
        parts.append("\(summary.failed) failed")
        if summary.cancelled { parts.append("stopped") }
        return parts.joined(separator: " · ")
    }
}
