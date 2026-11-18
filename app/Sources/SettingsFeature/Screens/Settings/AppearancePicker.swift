import SwiftUI
import AnalyzersKit

/// Auto, Light or Dark as three small pictures of a window, the chosen one outlined and its name under it: the way System
/// Settings offers its appearance. Drawn from shapes, so each picture follows nothing the person has set.
struct AppearancePicker: View {
    @Binding var selection: AppearancePreference

    var body: some View {
        HStack(spacing: 20) {
            ForEach(AppearancePreference.allCases) { choice in
                Button { selection = choice } label: {
                    VStack(spacing: 6) {
                        WindowThumbnail(choice: choice)
                            .frame(width: 96, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selection == choice ? Color.accentColor : Color.secondary.opacity(0.35),
                                              lineWidth: selection == choice ? 3 : 1))
                        Text(choice.title).font(.callout)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// A window drawn small: a title bar with its three dots, a sidebar, a few lines of content. Auto shows the light one on
/// the left half and the dark one on the right.
private struct WindowThumbnail: View {
    let choice: AppearancePreference

    var body: some View {
        switch choice {
        case .light: window(dark: false)
        case .dark: window(dark: true)
        case .auto:
            ZStack {
                window(dark: false)
                window(dark: true).mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        }
    }

    private func window(dark: Bool) -> some View {
        let background = dark ? Color(white: 0.16) : Color(white: 0.97)
        let sidebar = dark ? Color(white: 0.22) : Color(white: 0.90)
        let line = dark ? Color(white: 0.40) : Color(white: 0.75)
        return ZStack(alignment: .topLeading) {
            background
            HStack(spacing: 0) {
                sidebar.frame(width: 26)
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 30, height: 5)
                    RoundedRectangle(cornerRadius: 2).fill(line).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 40, height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(line).frame(height: 4)
                }
                .padding(.top, 20).padding(.horizontal, 8)
            }
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 5, height: 5) }
            }
            .padding(.leading, 5).padding(.top, 5)
        }
    }
}
