import SwiftUI

struct ContentView: View {
    @State private var count = 0
    @State private var bindingOnly = false
    @State private var unusedState = 0

    var body: some View {
        VStack {
            Button("Count: \(count)") {
                count += 1
            }
            Toggle("Binding", isOn: $bindingOnly)
        }
    }
}
