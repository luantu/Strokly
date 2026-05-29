import SwiftUI

struct KeyRecorderView: View {
    @Binding var key: String

    var body: some View {
        TextField("e.g. leftarrow, ], space, f1, escape, return", text: $key)
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
    }
}