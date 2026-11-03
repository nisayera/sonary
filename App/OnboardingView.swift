import SwiftUI
import SonaryCore
import SonaryUI

struct OnboardingView: View {
    let model: AppModel
    @State private var granted: Set<SonaryPermission> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let steps = onboardingSteps(for: model.registry.modules)
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Welcome to Sonary").font(.largeTitle.bold())
            Text("Sonary lives in your menu bar. Every feature is a module you can turn on or off.")
                .foregroundStyle(.secondary)

            if steps.isEmpty {
                GlassCard {
                    Text("No permissions are needed right now. Modules ask for access only when you turn them on.")
                }
            } else {
                GlassEffectContainer(spacing: Spacing.s) {
                    VStack(spacing: Spacing.s) {
                        ForEach(steps, id: \.permission) { step in
                            GlassCard {
                                HStack {
                                    Text(step.permission.rawValue).font(.headline)
                                    Spacer()
                                    if granted.contains(step.permission) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .accessibilityLabel("Granted")
                                    } else {
                                        Button("Allow") {
                                            Task {
                                                if await model.broker.ensure([step.permission]) {
                                                    granted.insert(step.permission)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Toggle("Open at login", isOn: Binding(
                get: { model.launchAtLogin.isEnabled },
                set: { model.launchAtLogin.set($0) }
            ))

            HStack {
                Spacer()
                Button("Done") {
                    model.completeOnboarding()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 460)
    }
}
