import SwiftUI
import CliptCore

/// The big search field with the type chips at its right end.
struct SearchRow: View {
    @Binding var query: String
    @Binding var filter: KindFilter
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused(focused)
            FilterChips(filter: $filter)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

private struct FilterChips: View {
    @Binding var filter: KindFilter

    var body: some View {
        HStack(spacing: 4) {
            ForEach(KindFilter.allCases, id: \.self) { kind in
                let on = kind == filter
                Text(kind.title)
                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : Color.primary.opacity(0.75))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07)),
                                in: .capsule)
                    .contentShape(.capsule)
                    // A tap, not a Button: nothing here may take focus from the search field.
                    .onTapGesture { filter = kind }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
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
