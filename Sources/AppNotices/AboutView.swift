import SwiftUI

/// The About screen as a form, for a sheet on the iPad: what the app is, Paizo's notices, credits and links.
public struct AboutView: View {
    private let info: AboutInfo

    public init(info: AboutInfo) {
        self.info = info
    }

    public var body: some View {
        Form {
            Section {
                Text(info.tagline)
                notice(info.communityUseNotice)
                notice(AboutInfo.trademarkNotice)
            }
            if !info.credits.isEmpty {
                Section("Credits") {
                    ForEach(info.credits, id: \.self, content: notice)
                }
            }
            Section("Links") {
                Link("Paizo's Community Use Policy", destination: AboutInfo.policyURL)
                Link("paizo.com", destination: AboutInfo.paizoURL)
                Link("Contact the Author", destination: info.contactURL)
            }
        }
        .navigationTitle("About \(info.appName)")
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The About screen in a sheet with a Done button.
public struct AboutSheet: View {
    private let info: AboutInfo
    @Environment(\.dismiss) private var dismiss

    public init(info: AboutInfo) {
        self.info = info
    }

    public var body: some View {
        NavigationStack {
            AboutView(info: info)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}
