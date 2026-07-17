import SwiftUI
import UniformTypeIdentifiers
import LearnerCore

/// First-run welcome surface. It shares the app's flush two-zone shell while
/// keeping the first decision deliberately small: use the bundled curriculum
/// or bring another reviewed pack.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    private var languageName: String { model.targetLanguageName }

    private var starterPack: (url: URL, pack: PackFile)? {
        AppModel.bundledPacks()
            .sorted { $0.pack.version > $1.pack.version }
            .first
    }

    private var bundledItemCount: Int? { starterPack?.pack.items.count }

    private var sampleSwap: (source: String, target: String, sentence: String) {
        guard let item = starterPack?.pack.items.first(where: {
            $0.fidelityTier == .exact && !$0.examples.isEmpty
        }) else {
            return ("source", "word", "Words appear in context.")
        }
        return (
            item.sourceLemma,
            item.target,
            item.examples[0].target
        )
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                brandPane
                    .frame(width: min(390, max(280, geometry.size.width * 0.3)))

                ScrollView {
                    welcomeContent
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                        .padding(.horizontal, 44)
                }
                .scrollIndicators(.hidden)
                .background(Theme.bg)
            }
        }
        .background(Theme.bg)
        .accessibilityElement(children: .contain)
    }

    private var brandPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CockatooMark(eyeColor: Theme.sideBg)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text("Cockatoo")
                    .font(.system(size: 15, weight: .semibold))
            }

            Spacer(minLength: 24)

            Text("LANGUAGE LEARNING, IN CONTEXT")
                .font(Theme.monoLabel())
                .kerning(0.8)
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 16)

            (Text("Learn ")
                .foregroundStyle(Theme.ink)
             + Text(languageName)
                .foregroundStyle(Theme.gold))
                .font(Theme.serif(38, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text("where you already read.")
                .font(.system(size: 25, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("Practice introduces each word. The web helps it stick.")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.inkMuted)
                .lineSpacing(3)
                .padding(.top, 18)

            Spacer(minLength: 22)

            sampleCard

            Spacer(minLength: 22)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Theme.gold)
                Text("LOCAL-FIRST · YOUR PACE")
                    .font(Theme.monoLabel(9.5))
                    .kerning(0.5)
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.top, Theme.chromeTop + 12)
        .padding(.horizontal, 32)
        .padding(.bottom, 26)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(Theme.sideBg)
    }

    private var sampleCard: some View {
        let sample = sampleSwap
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "safari")
                Text("ON A PAGE")
            }
            .font(Theme.monoLabel(9))
            .kerning(0.55)
            .foregroundStyle(Theme.inkFaint)
            .padding(.bottom, 12)

            highlightedSentence(sample.sentence, target: sample.target)
                .font(Theme.serif(18))
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.gold)
                    .frame(width: 3, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sample.target)
                        .font(Theme.serif(17, weight: .semibold))
                    Text("ORIGINAL · \(sample.source.uppercased())")
                        .font(Theme.monoLabel(8.5))
                        .kerning(0.4)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
            .padding(.top, 12)
        }
        .padding(15)
        .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example page swap. \(sample.target). Original: \(sample.source).")
    }

    private func highlightedSentence(_ sentence: String, target: String) -> Text {
        guard let range = sentence.range(of: target, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(sentence)
        }
        let prefix = String(sentence[..<range.lowerBound])
        let match = String(sentence[range])
        let suffix = String(sentence[range.upperBound...])
        return Text(prefix)
            + Text(match).foregroundColor(Theme.gold).underline(true, color: Theme.goldDeep)
            + Text(suffix)
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WELCOME TO COCKATOO")
                .font(Theme.monoLabel())
                .kerning(0.8)
                .foregroundStyle(Theme.inkFaint)

            Text("Start small. Keep reading.")
                .font(.system(size: 32, weight: .semibold))
                .padding(.top, 8)

            Text("Meet a few words in practice, then let the pages you already visit turn them into a habit.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkMuted)
                .lineSpacing(3)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 0) {
                onboardingStep(
                    systemImage: "rectangle.stack",
                    title: "Meet words in practice",
                    detail: "Short, focused sessions"
                )
                stepConnector
                onboardingStep(
                    systemImage: "safari",
                    title: "See them while reading",
                    detail: "Only after you meet them"
                )
                stepConnector
                onboardingStep(
                    systemImage: "cursorarrow.motionlines",
                    title: "Hover for the original",
                    detail: "Context stays one move away"
                )
            }
            .padding(.top, 28)

            fidelityNote
                .padding(.top, 12)

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.outcomeMissed)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .accessibilityLabel("Import error: \(error)")
            }

            HStack(spacing: 12) {
                Button("Start with \(languageName)") {
                    model.importBundledPack()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)

                Button("Import another pack…", action: pickPack)
                    .buttonStyle(.pill)
            }
            .padding(.top, 20)

            Text(starterPackCaption)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkFaint)
                .lineSpacing(2)
                .padding(.top, 11)
        }
        .padding(.vertical, Theme.chromeTop + 18)
    }

    private func onboardingStep(systemImage: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle().fill(Theme.surface)
                Circle().strokeBorder(Theme.line2)
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: 36, height: 36)

            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var stepConnector: some View {
        Rectangle()
            .fill(Theme.line2)
            .frame(height: 1)
            .frame(maxWidth: 30)
            .padding(.horizontal, 8)
            .padding(.top, 18)
            .accessibilityHidden(true)
    }

    private var fidelityNote: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.stageOnPages)
                .frame(width: 3, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vocabulary first. Grammar comes later.")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("A swap may not reproduce every agreement rule in the source sentence, so Cockatoo always marks what changed.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
    }

    private var starterPackCaption: String {
        if let bundledItemCount {
            return "Includes a \(bundledItemCount)-item starter pack. Practice works immediately; Safari reinforcement begins after you meet your first words."
        }
        return "Practice works immediately; Safari reinforcement begins after you meet your first words."
    }

    private func pickPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a Cockatoo language-pack JSON file"
        panel.prompt = "Import Pack"
        if panel.runModal() == .OK, let url = panel.url {
            model.importPack(from: url)
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    private struct PrimaryButton: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.onGold)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(hovering ? Theme.goldDeep : Theme.gold, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.1)))
                .offset(y: configuration.isPressed ? 1 : 0)
                .scaleEffect(configuration.isPressed ? 0.985 : 1)
                .shadow(color: Theme.gold.opacity(hovering ? 0.22 : 0), radius: 12, y: 4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.16), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
