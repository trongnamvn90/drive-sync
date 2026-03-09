import SwiftUI

struct SyncTab: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Timing") {
                LabeledContent("Debounce") {
                    Stepper(value: $appState.debounceSec, in: 5...300, step: 5) {
                        HStack {
                            TextField("", value: $appState.debounceSec, format: .number)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                            Text("sec")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Periodic sync") {
                    Stepper(value: $appState.periodicSyncMin, in: 5...60, step: 5) {
                        HStack {
                            TextField("", value: $appState.periodicSyncMin, format: .number)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                            Text("min")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("File Deletion") {
                Picker("On file delete:", selection: $appState.onDeleteAction) {
                    Text("Move to Trash").tag("Move to Trash")
                    Text("Delete permanently").tag("Delete permanently")
                }
            }
        }
        .formStyle(.grouped)
    }
}
