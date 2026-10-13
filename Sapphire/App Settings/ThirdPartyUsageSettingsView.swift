import SwiftUI

/// 父级 SettingsEditingSession 保存查询规则；独立密钥只通过 Keychain 保存。
struct ThirdPartyUsageSettingsView: View {
    @Binding var configuration: ThirdPartyUsageConfiguration
    let provider: AIUsageProvider
    @State private var draft: ThirdPartyUsageConfiguration

    init(configuration: Binding<ThirdPartyUsageConfiguration>, provider: AIUsageProvider) {
        self._configuration = configuration
        self.provider = provider
        self._draft = State(initialValue: configuration.wrappedValue)
    }

    @State private var queryKey = ""
    @State private var hasSavedKey = false
    @State private var keyStatus: String?
    @State private var testSnapshot: AIUsageSnapshot?
    @State private var testTask: Task<Void, Never>?
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(provider.displayName) · \(localized("Third-party Usage"))")
                    .font(.headline)
                Spacer()
                Toggle("Use third-party usage", isOn: $draft.enabled)
                    .labelsHidden()
                    .accessibilityLabel(Text("Use third-party usage"))
            }
            Text("Configure a read-only balance endpoint for the current provider. Missing values and reset times remain unknown.")
                .font(.caption).foregroundStyle(.secondary)
            if draft.enabled {
                endpointFields
                authenticationFields
                mappingFields
                testSection
            }
            HStack {
                Button("Save query settings") { configuration = draft }
                    .disabled(draft == configuration)
                Text("Changes take effect after saving. Testing uses the draft without saving it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .modifier(SettingsContainerModifier())
        .onAppear { hasSavedKey = AIUsageCredentialStore.hasQueryKey(for: provider, configuration: draft) }
        .onChange(of: configuration) { previous, updated in
            // 外部修改只同步未编辑的草稿，避免自动刷新覆盖正在填写的地址。
            if draft == previous { draft = updated }
            hasSavedKey = AIUsageCredentialStore.hasQueryKey(for: provider, configuration: draft)
            clearTest()
        }
        .onChange(of: draft) { _, _ in
            hasSavedKey = AIUsageCredentialStore.hasQueryKey(for: provider, configuration: draft)
            clearTest()
        }
        .onChange(of: queryKey) { _, newValue in
            if !newValue.isEmpty { keyStatus = nil }
            clearTest()
        }
        .onDisappear { clearTest() }
    }

    private var endpointFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Platform name", text: $draft.platformName, placeholder: "DeepSeek / Sub2API / NewAPI")
            field("Current provider API address", text: $draft.providerBaseURL, placeholder: "https://provider.example/v1")
            Text("For CLI credentials, this address must match the active CLI provider. An unrelated API Key will not be sent.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Picker("Usage template", selection: $draft.template) {
                    ForEach(ThirdPartyUsageTemplate.allCases) { template in
                        Text(template.displayName).tag(template)
                    }
                }
                Button("Apply template") { applyTemplate() }
                    .disabled(draft.template == .custom)
            }
            field("Usage query address", text: $draft.queryURL, placeholder: "https://provider.example/v1/usage")
            Text("Template fills the query address and JSON fields. Check your platform documentation before testing.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var authenticationFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Picker("Authentication", selection: $draft.authentication) {
                ForEach(ThirdPartyUsageAuthentication.allCases) { authentication in
                    Text(authentication.displayName).tag(authentication)
                }
            }
            if draft.authentication != .none {
                Picker("Query credentials", selection: $draft.credentialSource) {
                    ForEach(ThirdPartyUsageCredentialSource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                if draft.credentialSource == .separateQueryKey { keyFields }
            }
            field("NewAPI User ID (optional)", text: $draft.userID, placeholder: "123")
            if draft.template == .newAPI {
                Text("NewAPI requires an account Access Token and User ID, rather than a model API Key.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var keyFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Query Key or Access Token", text: $queryKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save query key") { saveKey() }
                    .disabled(queryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft != configuration)
                if hasSavedKey && draft == configuration {
                    Button("Remove saved key") { removeKey() }
                    Text("Query key saved in Keychain").font(.caption).foregroundStyle(.secondary)
                }
            }
            if draft != configuration {
                Text("Save query settings before saving a key for this destination.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Testing uses the entered key without saving it. Leave the field blank to use the saved query key.")
                .font(.caption2).foregroundStyle(.secondary)
            if let keyStatus { Text(keyStatus).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var mappingFields: some View {
        DisclosureGroup("JSON fields and reset time") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use dotted JSON paths, including array indices: data.balance or balance_infos.0.total_balance. Empty fields stay unknown.")
                    .font(.caption2).foregroundStyle(.secondary)
                field("Remaining field", text: $draft.remainingPath, placeholder: "data.balance")
                field("Used field (optional)", text: $draft.usedPath, placeholder: "data.used")
                field("Total field (optional)", text: $draft.totalPath, placeholder: "data.limit")
                field("Currency field (optional)", text: $draft.currencyPath, placeholder: "data.currency")
                HStack(alignment: .top, spacing: 12) {
                    field("Fallback unit", text: $draft.unit, placeholder: "USD / CNY / tokens")
                    field("Divide raw value by", text: $draft.scale, placeholder: "1")
                }
                Text("NewAPI starts at 500000 quota per USD. Adjust this divisor to match your platform's conversion rule.")
                    .font(.caption2).foregroundStyle(.secondary)
                field("Reset field (optional)", text: $draft.resetPath, placeholder: "data.resets_at")
                Picker("Reset format", selection: $draft.resetFormat) {
                    ForEach(ThirdPartyUsageResetFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(queryDestination)
                .font(.caption2).foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button("Test usage query") { runTest() }
                    .disabled(isTesting || draft.queryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isTesting { ProgressView().controlSize(.small) }
            }
            Text("Testing only sends a GET balance request. It shares the widget's refresh interval and rate-limit cooldown.")
                .font(.caption2).foregroundStyle(.secondary)
            if let snapshot = testSnapshot { testResult(snapshot) }
        }
    }

    private func testResult(_ snapshot: AIUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = snapshot.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(snapshot.amounts) { amount in
                VStack(alignment: .leading, spacing: 4) {
                    Text(amount.title).font(.caption.weight(.semibold))
                    resultRow("Remaining", value: amount.isUnlimited ? localized("Unlimited") : number(amount.remaining, unit: amount.unit))
                    resultRow("Used", value: number(amount.used, unit: amount.unit))
                    resultRow("Total", value: number(amount.total, unit: amount.unit))
                    resultRow("Reset time", value: date(amount.resetAt))
                }
            }
            ForEach(snapshot.balances) { balance in
                VStack(alignment: .leading, spacing: 4) {
                    Text(balance.currency).font(.caption.weight(.semibold))
                    resultRow("Remaining", value: number(balance.total, unit: balance.currency))
                    resultRow("Used", value: "—")
                    resultRow("Total", value: "—")
                    resultRow("Reset time", value: date(balance.resetAt))
                }
            }
            if snapshot.amounts.isEmpty && snapshot.balances.isEmpty {
                resultRow("Remaining", value: "—")
                resultRow("Reset time", value: "—")
            }
            resultRow("Last checked", value: date(snapshot.updatedAt))
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func resultRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().textSelection(.enabled)
        }
        .font(.caption)
    }

    private var queryDestination: String {
        let host = URL(string: draft.queryURL)?.host ?? localized("Not configured")
        let format = draft.authentication == .none
            ? localized("Read-only GET destination: %@")
            : localized("Read-only GET destination: %@. Query credentials are sent to this host.")
        return String(format: format, host)
    }

    private func applyTemplate() {
        var updated = draft
        updated.applyTemplate(draft.template, baseURL: draft.providerBaseURL)
        draft = updated
    }

    private func runTest() {
        clearTest()
        let testedConfiguration = draft
        let enteredKey = queryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let testKey = draft.credentialSource == .separateQueryKey && !enteredKey.isEmpty ? enteredKey : nil
        isTesting = true
        testTask = Task { @MainActor in
            let result = await AIUsageService.shared.test(provider: provider, configuration: testedConfiguration, queryKey: testKey)
            // 编辑配置、密钥或离开页面后，不得用旧响应误报新配置已通过。
            guard !Task.isCancelled, draft == testedConfiguration else { return }
            testSnapshot = result
            isTesting = false
            testTask = nil
        }
    }

    private func clearTest() {
        testTask?.cancel()
        testTask = nil
        isTesting = false
        testSnapshot = nil
    }

    private func saveKey() {
        do {
            try AIUsageCredentialStore.setQueryKey(queryKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider, configuration: configuration)
            queryKey = ""
            hasSavedKey = true
            keyStatus = localized("Query key saved in Keychain")
            clearTest()
        } catch {
            keyStatus = localized("Could not save query key to Keychain")
        }
    }

    private func removeKey() {
        do {
            try AIUsageCredentialStore.removeQueryKey(for: provider, configuration: configuration)
            queryKey = ""
            hasSavedKey = false
            keyStatus = localized("Saved query key removed")
            clearTest()
        } catch {
            keyStatus = localized("Could not remove query key from Keychain")
        }
    }

    private func number(_ value: Decimal?, unit: String) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return "\(formatter.string(from: value as NSDecimalNumber) ?? "—") \(unit)"
    }

    private func date(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .standard) ?? "—"
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "Third-party AI usage settings")
    }
}
