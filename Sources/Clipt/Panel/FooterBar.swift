import SwiftUI

/// ↩ Paste · ⌥↩ Paste as plain text · ⌘P Pin · ⌫ Delete · esc Close
struct FooterBar: View {
    var body: some View {
        HStack(spacing: 16) {
            hint("↩", "Paste")
            hint("⌥↩", "Paste as plain text")
            hint("⌘P", "Pin")
            hint("⌫", "Delete")
            Spacer(minLength: 0)
            hint("esc", "Close")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.primary.opacity(0.08), in: .rect(cornerRadius: 4))
            Text(label)
        }
    }
}
