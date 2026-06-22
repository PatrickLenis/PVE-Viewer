import SwiftUI

struct InstanceFormView: View {
    enum Mode {
        case add
        case edit(ProxmoxInstance)

        var title: String {
            switch self {
            case .add:
                return "Add Instance"
            case .edit:
                return "Edit Instance"
            }
        }
    }

    let mode: Mode
    let tokenStore: APITokenStoring
    let onSave: (ProxmoxInstance) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var link: String
    @State private var allowSelfSignedHTTPS: Bool
    @State private var configureAPI: Bool
    @State private var tokenID: String
    @State private var tokenSecret: String
    @State private var validationMessage: String?
    @State private var isValidatingServer = false

    init(mode: Mode, tokenStore: APITokenStoring, onSave: @escaping (ProxmoxInstance) -> Void) {
        self.mode = mode
        self.tokenStore = tokenStore
        self.onSave = onSave

        switch mode {
        case .add:
            _name = State(initialValue: "")
            _link = State(initialValue: "")
            _allowSelfSignedHTTPS = State(initialValue: false)
            _configureAPI = State(initialValue: false)
            _tokenID = State(initialValue: "")
            _tokenSecret = State(initialValue: "")
        case .edit(let instance):
            _name = State(initialValue: instance.name)
            _link = State(initialValue: instance.url.absoluteString)
            _allowSelfSignedHTTPS = State(initialValue: instance.allowSelfSignedHTTPS)
            _configureAPI = State(initialValue: instance.hasAPIToken)
            let savedToken = try? tokenStore.loadToken(for: instance.id)
            _tokenID = State(initialValue: savedToken?.tokenID ?? instance.apiDisplayName ?? "")
            _tokenSecret = State(initialValue: savedToken?.secret ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(mode.title)
                .font(.title2.weight(.semibold))

            Form {
                TextField("Display name", text: $name)
                TextField("Link", text: $link)
                Toggle("Allow self-signed HTTPS", isOn: $allowSelfSignedHTTPS)
                Toggle("Configure API token", isOn: $configureAPI.animation(.easeInOut(duration: 0.18)))

                if configureAPI {
                    Section("API Token") {
                        TextField("Token ID", text: $tokenID)
                            .textContentType(.username)
                        SecureField("Token secret", text: $tokenSecret)
                            .textContentType(.password)
                    }
                }
            }
            .formStyle(.grouped)

            if let validationMessage {
                Text(validationMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isValidatingServer ? "Checking..." : "Save") {
                    Task {
                        await save()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(
                    isValidatingServer ||
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func save() async {
        do {
            let normalizedURL = try URLNormalizer.normalize(link)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTokenID = tokenID.trimmingCharacters(in: .whitespacesAndNewlines)

            if configureAPI {
                guard !trimmedTokenID.isEmpty, !tokenSecret.isEmpty else {
                    throw InstanceFormValidationError.missingAPIToken
                }
            }

            if shouldValidateProxmoxServer(normalizedURL: normalizedURL) {
                isValidatingServer = true
                defer { isValidatingServer = false }
                try await ProxmoxServerValidationService().validate(
                    url: normalizedURL,
                    allowSelfSignedHTTPS: allowSelfSignedHTTPS
                )
            }

            let instance: ProxmoxInstance

            switch mode {
            case .add:
                instance = ProxmoxInstance(
                    name: trimmedName,
                    url: normalizedURL,
                    allowSelfSignedHTTPS: allowSelfSignedHTTPS,
                    hasAPIToken: configureAPI,
                    apiDisplayName: configureAPI ? trimmedTokenID : nil
                )
            case .edit(let existing):
                instance = ProxmoxInstance(
                    id: existing.id,
                    name: trimmedName,
                    url: normalizedURL,
                    allowSelfSignedHTTPS: allowSelfSignedHTTPS,
                    hasAPIToken: configureAPI,
                    apiDisplayName: configureAPI ? trimmedTokenID : nil
                )
            }

            if configureAPI {
                try tokenStore.saveToken(ProxmoxAPIToken(tokenID: trimmedTokenID, secret: tokenSecret), for: instance.id)
            } else if shouldDeleteExistingToken {
                try tokenStore.deleteToken(for: instance.id)
            }

            onSave(instance)
            dismiss()
        } catch {
            isValidatingServer = false
            withAnimation(.easeInOut(duration: 0.18)) {
                validationMessage = (error as? LocalizedError)?.errorDescription ?? "Invalid instance."
            }
        }
    }

    private func shouldValidateProxmoxServer(normalizedURL: URL) -> Bool {
        switch mode {
        case .add:
            return true
        case .edit(let existing):
            return existing.url != normalizedURL || existing.allowSelfSignedHTTPS != allowSelfSignedHTTPS
        }
    }

    private var shouldDeleteExistingToken: Bool {
        if case .edit(let existing) = mode {
            return existing.hasAPIToken
        }
        return false
    }
}

private enum InstanceFormValidationError: LocalizedError {
    case missingAPIToken

    var errorDescription: String? {
        switch self {
        case .missingAPIToken:
            return "Enter both the API token ID and token secret, or turn off API token setup."
        }
    }
}
