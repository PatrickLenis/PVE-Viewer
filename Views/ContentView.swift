import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: ProxmoxAppController
    @ObservedObject private var store: InstanceStore
    @ObservedObject private var dashboardStore: ProxmoxDashboardStore

    @State private var selectedInstanceID: ProxmoxInstance.ID?
    @State private var showingAddSheet = false
    @State private var editingInstance: ProxmoxInstance?
    @State private var webViewCommand = WebViewCommand()

    private var tokenStore: APITokenStoring {
        controller.tokenStore
    }

    init(controller: ProxmoxAppController) {
        self.controller = controller
        _store = ObservedObject(wrappedValue: controller.store)
        _dashboardStore = ObservedObject(wrappedValue: controller.dashboardStore)
    }

    private var selectedInstance: ProxmoxInstance? {
        guard let selectedInstanceID else { return nil }
        return store.instances.first { $0.id == selectedInstanceID }
    }

    private var selectedStatus: InstanceStatus {
        guard let selectedInstanceID else { return .unknown }
        return store.statuses[selectedInstanceID] ?? .unknown
    }

    var body: some View {
        NavigationSplitView {
            InstanceSidebarView(
                instances: store.instances,
                statuses: store.statuses,
                dashboardStates: dashboardStore.states,
                selection: $selectedInstanceID,
                addAction: { showingAddSheet = true },
                editAction: { editingInstance = $0 },
                deleteAction: delete
            )
        } detail: {
            DetailPane(
                instance: selectedInstance,
                status: selectedStatus,
                dashboardState: selectedInstance.map { dashboardStore.state(for: $0.id) } ?? .idle,
                command: $webViewCommand,
                refreshResourcesAction: refreshSelectedAPIResources,
                resourceAction: performResourceAction,
                isActionInProgress: dashboardStore.isActionInProgress
            )
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await controller.refreshAll(animated: true) }
                } label: {
                    Label("Refresh Status", systemImage: "dot.radiowaves.left.and.right")
                }
                .help("Refresh instance status")

                Button {
                    webViewCommand = WebViewCommand.reload()
                } label: {
                    Label("Reload Page", systemImage: "arrow.clockwise")
                }
                .disabled(!selectedStatus.canLoadPage)
                .help("Reload the selected Proxmox page")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            InstanceFormView(mode: .add, tokenStore: tokenStore) { instance in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    store.add(instance)
                    selectedInstanceID = instance.id
                }
                Task { await controller.refreshAll(animated: true) }
            }
        }
        .sheet(item: $editingInstance) { instance in
            InstanceFormView(mode: .edit(instance), tokenStore: tokenStore) { updated in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                    store.update(updated)
                    selectedInstanceID = updated.id
                }
                if !updated.hasAPIToken {
                    dashboardStore.remove(instanceID: updated.id)
                }
                Task { await controller.refreshAll(animated: true) }
            }
        }
        .task {
            if selectedInstanceID == nil {
                selectedInstanceID = store.instances.first?.id
            }
            await controller.refreshAll(animated: false)
            controller.startPolling()
        }
        .onChange(of: store.instances) { instances in
            if let selectedInstanceID, instances.contains(where: { $0.id == selectedInstanceID }) {
                Task { await dashboardStore.refreshAll(instances) }
            } else {
                selectedInstanceID = instances.first?.id
                Task { await dashboardStore.refreshAll(instances) }
            }
        }
        .onChange(of: controller.requestedSelectionID) { requestedID in
            guard let requestedID, store.instances.contains(where: { $0.id == requestedID }) else { return }
            selectedInstanceID = requestedID
        }
        .onChange(of: controller.requestedTokenSettingsID) { requestedID in
            guard let requestedID,
                  let instance = store.instances.first(where: { $0.id == requestedID }) else {
                return
            }
            selectedInstanceID = requestedID
            editingInstance = instance
        }
    }

    private func delete(_ instance: ProxmoxInstance) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            controller.delete(instance)
            if selectedInstanceID == instance.id {
                selectedInstanceID = store.instances.first?.id
            }
        }
        Task { await controller.refreshAll(animated: true) }
    }

    private func refreshSelectedAPIResources() {
        guard let selectedInstance else { return }
        Task { await dashboardStore.refresh(selectedInstance) }
    }

    private func performResourceAction(_ action: ProxmoxResourceAction, resource: ProxmoxResource) {
        guard let selectedInstance else { return }
        Task { await dashboardStore.perform(action, on: resource, instance: selectedInstance) }
    }
}

private struct DetailPane: View {
    let instance: ProxmoxInstance?
    let status: InstanceStatus
    let dashboardState: ProxmoxDashboardLoadState
    @Binding var command: WebViewCommand
    let refreshResourcesAction: () -> Void
    let resourceAction: (ProxmoxResourceAction, ProxmoxResource) -> Void
    let isActionInProgress: (ProxmoxResourceAction, ProxmoxResource) -> Bool

    @State private var isResourcesPanelCollapsed = true

    var body: some View {
        Group {
            if let instance {
                VStack(spacing: 0) {
                    if instance.hasAPIToken, !isResourcesPanelCollapsed {
                        VSplitView {
                            browserContent(for: instance)
                                .frame(minHeight: 240)

                            ResourcesPanelView(
                                state: dashboardState,
                                instance: instance,
                                collapseAction: {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        isResourcesPanelCollapsed = true
                                    }
                                },
                                isActionInProgress: isActionInProgress,
                                refreshAction: refreshResourcesAction,
                                resourceAction: resourceAction
                            )
                            .frame(minHeight: 170, idealHeight: 280, maxHeight: 520)
                        }
                    } else {
                        browserContent(for: instance)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if instance.hasAPIToken {
                            Divider()
                            CollapsedResourcesBar(
                                state: dashboardState,
                                expandAction: {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        isResourcesPanelCollapsed = false
                                    }
                                },
                                refreshAction: refreshResourcesAction
                            )
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("No Instance Selected")
                        .font(.title3.weight(.semibold))
                    Text("Add a Proxmox instance from the sidebar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func browserContent(for instance: ProxmoxInstance) -> some View {
        if status.canLoadPage {
            ProxmoxWebView(instance: instance, command: $command)
                .id("\(instance.id.uuidString)-\(instance.allowSelfSignedHTTPS)-\(status.rawValue)")
        } else {
            InstanceUnavailableView(instance: instance, status: status)
        }
    }
}

private struct CollapsedResourcesBar: View {
    let state: ProxmoxDashboardLoadState
    let expandAction: () -> Void
    let refreshAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label("Resources", systemImage: "list.bullet.rectangle")
                .font(.callout.weight(.semibold))

            if let snapshot = state.snapshot {
                Text("\(snapshot.resources.count) resources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if state.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if let message = state.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: refreshAction) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh API resources")

            Button(action: expandAction) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Expand resources")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct InstanceUnavailableView: View {
    let instance: ProxmoxInstance
    let status: InstanceStatus

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: status.unavailableIconName)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(status == .error ? .red : .secondary)

            Text(status.unavailableTitle)
                .font(.title3.weight(.semibold))

            Text(status.unavailableMessage(for: instance))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension InstanceStatus {
    var canLoadPage: Bool {
        self == .online || self == .tlsWarning
    }

    var unavailableIconName: String {
        switch self {
        case .error:
            return "exclamationmark.triangle"
        case .offline, .unknown:
            return "wifi.slash"
        case .online, .tlsWarning:
            return "checkmark.circle"
        }
    }

    var unavailableTitle: String {
        switch self {
        case .error:
            return "Connection Error"
        case .offline:
            return "Instance Offline"
        case .unknown:
            return "Checking Status"
        case .online, .tlsWarning:
            return ""
        }
    }

    func unavailableMessage(for instance: ProxmoxInstance) -> String {
        let host = instance.url.host ?? instance.url.absoluteString
        switch self {
        case .error:
            if instance.allowSelfSignedHTTPS {
                return "\(host) is reachable, but returned an error. The Proxmox page is blocked until the status is online or TLS warning."
            }
            return "\(host) returned an HTTP or HTTPS error. Enable Allow self-signed HTTPS only if this instance uses a trusted local certificate."
        case .offline:
            return "\(host) is unreachable or timed out. Refresh status after the instance is back online."
        case .unknown:
            return "Waiting for the first status check for \(host)."
        case .online, .tlsWarning:
            return ""
        }
    }
}

extension Color {
    static let proxmoxOrange = Color(red: 0.89, green: 0.38, blue: 0.08)
}
