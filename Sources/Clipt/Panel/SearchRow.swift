import SwiftUI
import CliptCore

/// The search field with the type filter, a small segmented control, at its right end.
struct SearchRow: View {
    @Binding var query: String
    @Binding var filter: KindFilter
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused(focused)
            FilterChips(filter: $filter)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 40)
    }
}

/// One faint capsule; the chosen kind sits in a raised light capsule inside it.
private struct FilterChips: View {
    @Binding var filter: KindFilter
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(KindFilter.allCases, id: \.self) { kind in
                let on = kind == filter
                Text(kind.title)
                    .font(.system(size: 10.5, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background {
                        if on {
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                        }
                    }
                    .contentShape(.capsule)
                    // A tap, not a Button: nothing here may take focus from the search field.
                    .onTapGesture { filter = kind }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(.primary.opacity(colorScheme == .dark ? 0.07 : 0.05), in: .capsule)
    }
}

extension KindFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .images: "Images"
        case .links: "Links"
        }
    }
}
