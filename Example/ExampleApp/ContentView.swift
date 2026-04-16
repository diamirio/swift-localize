import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("welcome_title")
            Text("welcome_subtitle")
            Button(action: {}) {
                Text("button_get_started")
            }
            Divider()
            Text("settings_language_label")
            Text("error_network_unavailable")
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
