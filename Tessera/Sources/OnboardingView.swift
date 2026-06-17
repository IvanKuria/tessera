import SwiftUI
import KalshiKit

/// Connect-your-key onboarding. A Kalshi-clean explainer that takes a Key ID and
/// an RSA private key (PEM), validates them, and stores the key ONLY in the
/// macOS Keychain. Defaults to the DEMO environment.
struct OnboardingView: View {
    var account: AccountStore
    var onDone: () -> Void = {}

    @State private var keyID: String = ""
    @State private var pem: String = ""
    @State private var selectedEnv: AccountStore.Env = .demo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                guide
                envPicker
                fields
                disclaimers
                connectButton
                if let error = account.lastError {
                    errorBanner(error)
                }
            }
            .padding(28)
            .frame(maxWidth: 460, alignment: .leading)
        }
        .background(Theme.bg)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.subtle))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)  // Esc also dismisses
            .padding(12)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Wordmark()
            Text("Connect your Kalshi API key")
                .font(Theme.condensed(26, .semibold))
                .foregroundStyle(Theme.text)
            Text("Trade Kalshi markets from your Mac. Your key stays on this device.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(Theme.num(11, .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.yes))
                    Text(step)
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.subtle))
    }

    private var steps: [String] {
        [
            "Sign in at kalshi.com, then open Account → API Keys.",
            "Create a new key and copy its Key ID.",
            "Download the RSA private key it gives you (a .pem / .key file).",
            "Paste the Key ID and the full private key below."
        ]
    }

    private var envPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("ENVIRONMENT")
            HStack(spacing: 8) {
                envChip(.demo, title: "Demo", subtitle: "Practice — no real money")
                envChip(.production, title: "Production", subtitle: "Real orders, real money")
            }
            if selectedEnv == .production {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.no)
                    Text("Production places REAL orders with REAL money.")
                        .font(Theme.ui(11.5, .medium))
                        .foregroundStyle(Theme.no)
                }
            }
        }
    }

    private func envChip(_ value: AccountStore.Env, title: String, subtitle: String) -> some View {
        let isSelected = selectedEnv == value
        let tint = value == .production ? Theme.no : Theme.yes
        return Button {
            selectedEnv = value
            account.setEnv(value)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.ui(13.5, .semibold))
                    .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
                Text(subtitle)
                    .font(Theme.ui(10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? tint.opacity(0.07) : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? tint.opacity(0.55) : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("KEY ID")
                TextField("e.g. 1a2b3c4d-…", text: $keyID)
                    .textFieldStyle(.plain)
                    .font(Theme.num(13))
                    .foregroundStyle(Theme.text)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("RSA PRIVATE KEY (PEM)")
                TextEditor(text: $pem)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(height: 150)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                    .overlay(alignment: .topLeading) {
                        if pem.isEmpty {
                            Text("-----BEGIN RSA PRIVATE KEY-----\n…\n-----END RSA PRIVATE KEY-----")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private var disclaimers: some View {
        VStack(alignment: .leading, spacing: 6) {
            disclaimerRow("Unofficial app — not affiliated with, or endorsed by, Kalshi.")
            disclaimerRow("Your key is stored only in your Mac's Keychain and is sent only to Kalshi.")
            disclaimerRow("Not financial advice. Trading involves risk. Use at your own risk.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.subtle))
    }

    private func disclaimerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 1)
            Text(text)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectButton: some View {
        Button {
            Task {
                let ok = await account.signIn(keyID: keyID, pem: pem)
                if ok {
                    pem = ""   // don't keep the PEM in view state any longer than needed
                    onDone()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if account.isWorking {
                    ProgressView().controlSize(.small).tint(Theme.onAccent)
                }
                Text(account.isWorking ? "Connecting…" : "Connect")
                    .font(Theme.ui(15, .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Capsule().fill(Theme.yes))
            .opacity(canConnect ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!canConnect || account.isWorking)
    }

    private var canConnect: Bool {
        !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.no)
            Text(message)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.no)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.no.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.no.opacity(0.25), lineWidth: 1))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(10, .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
    }
}
