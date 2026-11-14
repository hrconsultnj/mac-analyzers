import AnalyzersKit
import SwiftUI
import UIComponents

/// The flow's bottom bar: where you are, Back, Set Up Later, Not Now (on every step but the first, and not on Done), and
/// the step's one primary button (Return).
struct WelcomeBottomBar: View {
    let position: Int
    let count: Int
    let isFirst: Bool
    let isLast: Bool
    let step: WelcomeStep
    let primary: String
    let busy: Bool
    let back: () -> Void
    let later: () -> Void
    let notNow: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        HStack {
            Text("Step \(position) of \(count)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if !isLast { Button(Names.Welcome.setUpLater, action: later) }
            Button(Names.Welcome.back, action: back).disabled(isFirst || busy)
            if !isFirst, !isLast { Button(Names.Welcome.notNow, action: notNow).disabled(busy) }
            Button(primary, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
        }
        .padding(.horizontal, Tokens.Space.l)
        .padding(.vertical, Tokens.Space.m)
    }
}
