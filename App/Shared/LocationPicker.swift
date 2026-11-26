import SwiftUI

/// Location picker, Choose Folder… and Remember, shared by the scanning tools.
struct LocationPicker: View {
    @Bindable var location: ScanLocationModel
    /// Called after the user picks another location.
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Location", selection: Binding(
                get: { location.choice },
                set: { choice in
                    location.choice = choice
                    onChange()
                }
            )) {
                ForEach(location.choices) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .frame(maxWidth: 220)

            Button("Choose Folder…") {
                if location.chooseFolder() { onChange() }
            }

            Toggle("Remember", isOn: $location.remembers)
                .toggleStyle(.checkbox)
                .help("Start from this location next time")
        }
    }
}
