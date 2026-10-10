import DesqueezeCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false
    @State private var notesHeight: CGFloat = 0
    /// True while the custom field has the keyboard focus.
    @FocusState private var customFocused: Bool
    /// False until the window has opened. A focus before that is AppKit's,
    /// not the person's.
    @State private var windowHasOpened = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.exiftoolMissing { missingExiftool }
            dropZone
            factorRow
            // Only for a folder with a pending ARW that can convert (design
            // 14.4). Between the factor and the Run button, so the person
            // reads it before the click.
            if model.showsTrashOriginals { originalsRow }
            actionRow
            if model.isRunning { runProgress }
            if let summary = model.summary { result(summary) }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            // AppKit gives the custom field the keyboard focus when the
            // window opens. Nobody chose that, so the field gives the focus
            // up here. That first focus arrives before this block runs, so
            // `windowHasOpened` keeps it from selecting the custom factor.
            // `@FocusState` does all of it: no AppKit call is needed.
            DispatchQueue.main.async {
                customFocused = false
                windowHasOpened = true
            }
        }
    }

    // MARK: Parts

    private var missingExiftool: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The sentence and the command are the core's, so the command
            // line tool says the same words.
            SymbolLine(.attention, ToolLocator.exiftoolMissing)
                .font(.callout.weight(.medium))
            Text("Install it in Terminal, then open Desqueeze again:")
                .font(.callout)
            Text(ToolLocator.exiftoolInstallCommand)
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
                .accessibilityHidden(true)
            if let name = model.folderName {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !model.arwsCannotConvert {
                if let counts = model.countsLine {
                    Text(counts)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // One converter is missing, and every ARW still converts.
                // A quiet line: it is no error, and it asks for nothing.
                // It is longer than the window is wide, so it wraps.
                if let advice = model.converterAdvice {
                    SymbolLine(.information, advice, quiet: true)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            // Also beside counts that are there: a scan after the app became
            // active leaves the old counts and turns Run and Remove off.
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Reading the folder")
            }
            if model.arwsCannotConvert || !model.folderMessages.isEmpty || model.dropMessage != nil {
                // One block with one left edge, so the symbols make a column.
                VStack(alignment: .leading, spacing: 6) {
                    // Neither converter is installed, and ARW files wait: one
                    // condition, so one warning (design 13.5). The counts
                    // line carries the warning symbol, as the read-only
                    // message does. The install line below it informs: the
                    // information symbol, and primary text. Both lines wrap,
                    // and are not cut. Only this view decides the symbols;
                    // the model hands over the two lines and
                    // `arwsCannotConvert`.
                    if model.arwsCannotConvert {
                        if let counts = model.countsLine { zoneMessage(counts) }
                        if let advice = model.converterAdvice {
                            SymbolLine(.information, advice)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                    ForEach(model.folderMessages, id: \.self) { zoneMessage($0) }
                    // The system's words for a lock call that failed
                    // (design 13.9), below the plain sentence, as a note of
                    // the result shows its detail: small, quiet, and a
                    // person can copy them.
                    if let detail = model.folderMessageDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    // A wrong drop gets its own line. It never hides a line above.
                    if let message = model.dropMessage { zoneMessage(message) }
                }
                .padding(.vertical, 2)
            }
            Button("Choose folder") { model.chooseFolder() }
                .disabled(model.isRunning)
            Text("or drag a folder here")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(showsDropTarget ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(showsDropTarget ? Color.accentColor : Color.secondary.opacity(0.5),
                              style: StrokeStyle(lineWidth: showsDropTarget ? 2 : 1, dash: [5, 4]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls)
        } isTargeted: {
            isTargeted = $0
        }
    }

    /// True when a drag is over the zone and a drop would be taken. During a
    /// run a drop is refused, so the zone does not light up.
    private var showsDropTarget: Bool { isTargeted && model.acceptsDrop }

    /// A message about the folder. The symbol says "look at this", so the
    /// text needs no colour.
    private func zoneMessage(_ text: String) -> some View {
        SymbolLine(.attention, text)
            .font(.callout)
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
                customField
            }
            .disabled(model.isRunning)
            if let error = model.customError {
                SymbolLine(.attention, error)
                    .font(.caption)
            }
        }
    }

    /// One button for each preset, selected or not. The selection is a
    /// parameter of its style, not a second button: a second button is a new
    /// view, and the keyboard focus would not follow the selection to it.
    private func presetButton(_ preset: SqueezeFactor) -> some View {
        let isSelected = model.choice == .preset(preset)
        return Button {
            model.select(preset)
            // The field gives up the focus, so a later click into it is a
            // change of focus, and selects the custom factor again.
            customFocused = false
        } label: {
            Text(preset.label).frame(maxWidth: .infinity)
        }
        .buttonStyle(FactorButtonStyle(isSelected: isSelected))
        .accessibilityLabel("Squeeze factor \(preset.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customField: some View {
        let isSelected = model.choice == .custom
        // The example has its own colour. With the system's colour, a field
        // that is off during a run shows the example as dark as a value.
        return TextField("Custom squeeze factor", text: $model.customText,
                         prompt: Text("1.6").foregroundStyle(.tertiary))
            .textFieldStyle(.roundedBorder)
            .focused($customFocused)
            .frame(width: 72)
            // The selected field gets a check mark and a border in the text
            // colour. The accent colour stays off it: on a Mac whose accent
            // is red, an accent border reads as an error. The system's focus
            // ring has the accent colour too, so it is off. The field with
            // the focus is always the selected one, so the border shows it.
            .focusEffectDisabled()
            .overlay(alignment: .trailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .padding(.trailing, 7)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.75), lineWidth: 1.5)
                }
            }
            // A click into the field, or a Tab to it, selects the custom
            // factor. A change of the text alone would come too late: the
            // field would have the caret while a preset still looked selected.
            .onChange(of: customFocused) { _, isFocused in
                if isFocused, windowHasOpened { model.selectCustom() }
            }
            .accessibilityLabel("Custom squeeze factor")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The box that asks the run to move each original ARW to the Trash
    /// (design 14.4). The model keeps it off unless the person ticks it, and
    /// off again after every run. The label and the line under it are the
    /// core's.
    private var originalsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(FolderText.trashOriginalsLabel,
                   isOn: Binding(get: { model.trashOriginals }, set: { model.setTrashOriginals($0) }))
                .toggleStyle(.checkbox)
                // Off while a run or a scan is in work: the box cannot
                // change then.
                .disabled(!model.canChangeTrashOriginals)
                .accessibilityLabel(FolderText.trashOriginalsLabel)
            // What the run will do, with the count. It wraps, and is not cut.
            if let line = model.trashOriginalsLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if model.isRunning {
                // One button for Cancel and for "Finishing…". After the
                // click, and after the job has returned, it is off: a second
                // click on the same spot finds no Run button under it.
                Button(action: model.cancel) {
                    Text(model.isFinishing ? "Finishing…" : "Cancel").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .disabled(model.isFinishing)
            } else {
                Button(action: model.run) {
                    Text(model.runLabel).frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRun)
            }
            Button("Remove", action: model.remove)
                .controlSize(.large)
                .disabled(!model.canRemove)
                .help("Set every DNG back to no stretch")
        }
    }

    /// The bar has no value before the job completes its first step: the
    /// run's own scan comes first, and can take seconds.
    private var runProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Two views, on purpose. One view whose value goes from nil to a
            // number stays indeterminate on macOS.
            if let progress = model.progress {
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                    .accessibilityLabel("Progress of the run")
                    .accessibilityValue("\(progress.completed) of \(progress.total)")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Progress of the run")
            }
            Text(model.progressLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func result(_ summary: RunSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // One line from the core, so the window and the command line
            // tool show the same counts. It shows "blocked" when it is not
            // zero. The symbol carries the outcome, and the counts stay in
            // the text colour.
            SymbolLine(summary.needsAttention ? .attention : (summary.cancelled ? .stopped : .done),
                       summary.countsLine)
                .font(.callout.weight(.medium))
            // Both converters did work: how many photos each converted. The
            // core makes the line, and the command line tool shows the same.
            if let converters = summary.convertersLine {
                Text(converters)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Only after a run that was asked to move the originals (design
            // 14.3). The core makes the line, and VoiceOver heard it with
            // the counts when the run ended.
            if let originals = summary.originalsLine {
                Text(originals).font(.callout)
            }
            if let left = model.unconvertedLine(summary) {
                Text(left).font(.callout)
            }
            // Only after a run that set a photo (design 4.4). The core
            // decides, so the tool shows the line for the same runs.
            if let lightroom = summary.lightroomLine {
                Text(lightroom)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !summary.notes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(summary.notes) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                // A DNG with no full match is converted,
                                // an original that stays is no failure,
                                // and no more is a volume that gives no
                                // folder lock. Each note informs, so it
                                // has the symbol of information, and the
                                // result above keeps its "done" symbol.
                                if AppModel.isInformation(note) {
                                    SymbolLine(.information, note.name).font(.callout.weight(.medium))
                                } else {
                                    Text(note.name).font(.callout.weight(.medium))
                                }
                                Text(note.message).font(.callout)
                                if let detail = note.detail {
                                    // A restore failure has two lines here.
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { notesHeight = $0 }
                }
                // A scroll view has no height of its own, and this window
                // takes its size from its content. So the list gets the
                // height of its rows, up to a limit.
                .frame(height: min(notesHeight, 160))
            }
        }
    }
}

/// One line of text behind a symbol. The symbol carries the meaning, so no
/// meaning is in a colour alone: the Mac's accent colour can be the red of
/// an error. VoiceOver reads the symbol's meaning, then the text.
private struct SymbolLine: View {
    enum Meaning {
        /// `information` says "good to know". It is never an error, and it
        /// asks for nothing.
        case attention, done, stopped, information

        var symbol: String {
            switch self {
            case .attention: return "exclamationmark.triangle.fill"
            case .done: return "checkmark.circle.fill"
            case .stopped: return "stop.circle.fill"
            case .information: return "info.circle"
            }
        }

        var spoken: String {
            switch self {
            case .attention: return "Needs attention"
            case .done: return "Done"
            case .stopped: return "Stopped"
            case .information: return "Information"
            }
        }

        var colour: Color {
            switch self {
            case .attention: return .orange
            case .done: return .green
            case .stopped, .information: return .secondary
            }
        }
    }

    private let meaning: Meaning
    private let text: String
    private let quiet: Bool

    /// - Parameter quiet: true shows the text in the secondary text style,
    ///   for a line that only informs.
    init(_ meaning: Meaning, _ text: String, quiet: Bool = false) {
        self.meaning = meaning
        self.text = text
        self.quiet = quiet
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: meaning.symbol)
                .foregroundStyle(meaning.colour)
                .accessibilityLabel(meaning.spoken)
            Text(text)
                .foregroundStyle(quiet ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The look of a preset: filled with the accent colour when it is the
/// selected factor, grey when it is not.
private struct FactorButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, isSelected: isSelected)
    }

    private struct Face: View {
        let configuration: Configuration
        let isSelected: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 6)
            configuration.label
                .padding(.vertical, 3)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)),
                            in: shape)
                .overlay { if configuration.isPressed { shape.fill(Color.black.opacity(0.12)) } }
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(shape)
        }
    }
}
