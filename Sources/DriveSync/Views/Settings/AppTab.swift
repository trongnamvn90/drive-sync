import SwiftUI

struct AppTab: View {
    @Bindable var appState: AppState
    @State private var logsPaused = false
    @State private var displayedEntries: [LogEntry] = []
    @State private var pauseBuffer: [LogEntry] = []
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Launch at Login", isOn: $appState.launchAtLogin)
                        .toggleStyle(.checkbox)
                    Toggle("Notifications", isOn: $appState.showNotifications)
                        .toggleStyle(.checkbox)
                }

                Section {
                    LabeledContent("Symlink") {
                        TextField("", text: $appState.symlinkPath)
                            .frame(width: 200)
                    }
                }

                Section {
                    Picker("Log level:", selection: $appState.logLevel) {
                        Text("debug").tag("debug")
                        Text("info").tag("info")
                        Text("warn").tag("warn")
                        Text("error").tag("error")
                    }
                    .frame(width: 200)

                    LabeledContent("Keep logs") {
                        Stepper(value: $appState.keepLogsDays, in: 1...365, step: 1) {
                            HStack {
                                TextField("", value: $appState.keepLogsDays, format: .number)
                                    .frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                                Text("days")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            // Live logs section
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Logs (live)")
                        .font(.headline)
                    Spacer()
                    Button(logsPaused ? "▶ Resume" : "⏸ Pause") {
                        if logsPaused {
                            // Resume: flush pause buffer
                            displayedEntries.append(contentsOf: pauseBuffer)
                            pauseBuffer.removeAll()
                        }
                        logsPaused.toggle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(displayedEntries) { entry in
                                HStack(spacing: 6) {
                                    Text(entry.time)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 55, alignment: .trailing)
                                    Image(systemName: entry.level.icon)
                                        .font(.caption)
                                        .foregroundStyle(colorForLevel(entry.level))
                                        .frame(width: 14)
                                    Text(entry.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(colorForLevel(entry.level))
                                }
                                .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .padding(8)
                    .background(.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onChange(of: displayedEntries.count) {
                        if !logsPaused, let last = displayedEntries.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Button("Open Log File") {
                    appState.openLogFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        }
        .task {
            let stream = await LogManager.shared.makeStream()
            streamTask = Task {
                for await entry in stream {
                    if logsPaused {
                        pauseBuffer.append(entry)
                    } else {
                        displayedEntries.append(entry)
                    }
                }
            }
        }
        .onDisappear {
            streamTask?.cancel()
            streamTask = nil
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info:  return .primary
        case .warn:  return .orange
        case .error: return .red
        }
    }
}
