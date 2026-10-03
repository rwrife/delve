import DelveKit
import SwiftUI

/// M1 launch placeholder. Later milestones replace this home screen with the
/// entrance screen (new delve / resume) as the exploration UI lands (issue #4).
struct BootstrapHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "scroll")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Delve")
                        .font(.largeTitle.bold())
                    Text("A local-first fixed-dungeon puzzle crawler.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Native app foundation is ready", systemImage: "checkmark.circle")
                        Text("Dungeon engine, quest journal, and room exploration arrive in the next milestones.")
                            .foregroundStyle(.secondary)
                        Text("Domain core milestone: \(DelveKit.milestone).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .navigationTitle("Home")
        }
        .accessibilityIdentifier("bootstrap.home")
    }
}
