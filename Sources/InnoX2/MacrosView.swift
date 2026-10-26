import SwiftUI
import AppKit

struct MacrosView: View {
    @EnvironmentObject var mouse: Mouse
    @State private var slot = 0

    var body: some View {
        HSplitView {
            List(0..<Macro.slots, id: \.self, selection: Binding(get: { slot }, set: { slot = $0 ?? 0 })) { s in
                HStack {
                    Image(systemName: (mouse.macros[s]?.events.isEmpty ?? true) ? "square.dashed" : "keyboard")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text("Macro \(s + 1)")
                    Spacer()
                    if let m = mouse.macros[s] {
                        Text(m.events.isEmpty ? "empty" : "\(m.events.count) steps")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .tag(s)
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .frame(minWidth: 170, maxWidth: 220)
            .onAppear {
                // Fill in the list so you can see which slots are used.
                for s in 0..<Macro.slots where mouse.macros[s] == nil { mouse.loadMacro(s) }
            }

            MacroEditor(slot: slot)
                .id(slot)
                .frame(minWidth: 360)
        }
    }
}

struct MacroEditor: View {
    @EnvironmentObject var mouse: Mouse
    let slot: Int
    @State private var draft = Macro()
    @State private var loadedFromMouse = false
    @State private var recording = false
    @State private var realTiming = true
    @State private var fixedDelay = 20
    @State private var monitor: Any?
    @State private var lastEventTime: TimeInterval?

    var dirty: Bool { loadedFromMouse && mouse.macros[slot] != draft }
    var size: Int { draft.encoded.count }

    var body: some View {
        VStack(spacing: 0) {
            if !loadedFromMouse {
                Spacer()
                ProgressView("Reading macro \(slot + 1)…")
                Spacer()
            } else {
                toolbar
                Divider()
                if draft.events.isEmpty {
                    Spacer()
                    Text(recording ? "Type the keys you want to record…" : "Empty. Press Record and type, or add clicks.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    eventList
                }
                Divider()
                footer
            }
        }
        .onAppear {
            if let m = mouse.macros[slot] { draft = m; loadedFromMouse = true } else { mouse.loadMacro(slot) }
        }
        .onChange(of: mouse.macros[slot]) {
            if !loadedFromMouse, let m = mouse.macros[slot] { draft = m; loadedFromMouse = true }
        }
        .onDisappear(perform: stopRecording)
    }

    var toolbar: some View {
        HStack {
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Label(recording ? "Stop" : "Record", systemImage: recording ? "stop.circle.fill" : "record.circle")
                    .foregroundStyle(recording ? .red : .primary)
            }
            Menu("Add click") {
                ForEach(MacroButton.allCases, id: \.self) { b in
                    Button(b.title) {
                        draft.events += [MacroEvent(kind: .button(b), down: true, delay: fixedDelay),
                                         MacroEvent(kind: .button(b), down: false, delay: fixedDelay)]
                    }
                }
            }
            .fixedSize()
            Spacer()
            Toggle("Real timing", isOn: $realTiming)
                .help("Off: every recorded event waits the fixed delay instead of how long you actually took.")
            if !realTiming {
                TextField("", value: $fixedDelay, format: .number).frame(width: 50)
                Text("ms")
            }
        }
        .padding(10)
    }

    var eventList: some View {
        List {
            ForEach($draft.events) { $e in
                HStack {
                    Image(systemName: e.down ? "arrow.down.circle.fill" : "arrow.up.circle")
                        .foregroundStyle(e.down ? Color.accentColor : .secondary)
                    Text(e.title)
                    Text(e.down ? "down" : "up").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("wait").font(.caption).foregroundStyle(.secondary)
                    TextField("", value: $e.delay, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("ms").font(.caption).foregroundStyle(.secondary)
                    Button {
                        draft.events.removeAll { $0.id == e.id }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            .onMove { draft.events.move(fromOffsets: $0, toOffset: $1) }
        }
    }

    var footer: some View {
        HStack {
            Stepper("Repeat \(draft.repeatCount)×", value: $draft.repeatCount, in: 1...999)
                .help("Used when the button is set to \"Run\" mode.")
            Spacer()
            Text("\(size)/\(Macro.maxBytes) bytes")
                .font(.caption.monospacedDigit())
                .foregroundStyle(size > Macro.maxBytes ? .red : .secondary)
            Button("Clear") { draft.events = [] }
                .disabled(draft.events.isEmpty)
            Button("Revert") { if let m = mouse.macros[slot] { draft = m } }
                .disabled(!dirty)
            Button("Save to mouse") {
                stopRecording()
                for i in draft.events.indices { draft.events[i].delay = max(1, min(65535, draft.events[i].delay)) }
                mouse.saveMacro(slot, draft)
            }
            .keyboardShortcut("s")
            .buttonStyle(.borderedProminent)
            .disabled(!dirty || size > Macro.maxBytes)
        }
        .padding(10)
    }

    // MARK: - recording

    func startRecording() {
        recording = true
        lastEventTime = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { ev in
            record(ev)
            return nil   // swallow so recorded shortcuts don't trigger anything in the app
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    func record(_ ev: NSEvent) {
        guard let usage = HIDKeys.fromMac[ev.keyCode] else { return }
        let down: Bool
        switch ev.type {
        case .keyDown:
            if ev.isARepeat { return }
            down = true
        case .keyUp:
            down = false
        case .flagsChanged:
            guard let flag = Self.modifierFlag[ev.keyCode] else { return }
            down = ev.modifierFlags.contains(flag)
        default:
            return
        }
        if realTiming, let last = lastEventTime, !draft.events.isEmpty {
            draft.events[draft.events.count - 1].delay = max(1, min(65535, Int((ev.timestamp - last) * 1000)))
        }
        lastEventTime = ev.timestamp
        draft.events.append(MacroEvent(kind: .key(usage), down: down, delay: fixedDelay))
    }

    static let modifierFlag: [UInt16: NSEvent.ModifierFlags] = [
        55: .command, 54: .command, 56: .shift, 60: .shift, 58: .option, 61: .option, 59: .control, 62: .control,
    ]
}
