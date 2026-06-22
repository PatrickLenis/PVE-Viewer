import AppKit
import SwiftUI

struct ProxmoxMenuBarView: View {
    @ObservedObject var store: InstanceStore
    @ObservedObject var dashboardStore: ProxmoxDashboardStore

    let openMainWindow: () -> Void
    let openInstance: (ProxmoxInstance) -> Void
    let openAPISettings: (ProxmoxInstance) -> Void
    let isActionInProgress: (ProxmoxResourceAction, ProxmoxResource) -> Bool
    let resourceAction: (ProxmoxResourceAction, ProxmoxResource, ProxmoxInstance) -> Void
    let refreshAction: () -> Void

    @State private var selectedInstanceID: ProxmoxInstance.ID?

    private var selectedInstance: ProxmoxInstance? {
        if let selectedInstanceID,
           let instance = store.instances.first(where: { $0.id == selectedInstanceID }) {
            return instance
        }
        return store.instances.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PVE Viewer")
                    .font(.headline)
                Spacer()
                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }

            if store.instances.isEmpty {
                Text("No saved instances.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if let selectedInstance {
                instancePicker

                MenuBarInstanceCard(
                    instance: selectedInstance,
                    status: store.statuses[selectedInstance.id] ?? .unknown,
                    state: dashboardStore.state(for: selectedInstance.id),
                    openInstance: { openInstance(selectedInstance) },
                    openAPISettings: { openAPISettings(selectedInstance) },
                    isActionInProgress: isActionInProgress,
                    resourceAction: { action, resource in
                        resourceAction(action, resource, selectedInstance)
                    }
                )
            }

            Divider()

            HStack {
                Button("Open App") {
                    openMainWindow()
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 430)
        .onAppear {
            selectedInstanceID = selectedInstance?.id
        }
        .onChange(of: store.instances) { instances in
            guard let selectedInstanceID,
                  instances.contains(where: { $0.id == selectedInstanceID }) else {
                self.selectedInstanceID = instances.first?.id
                return
            }
        }
    }

    private var instancePicker: some View {
        Picker("Instance", selection: Binding(
            get: { selectedInstance?.id ?? store.instances.first?.id },
            set: { selectedInstanceID = $0 }
        )) {
            ForEach(store.instances) { instance in
                Text(instance.name)
                    .tag(Optional(instance.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MenuBarInstanceCard: View {
    let instance: ProxmoxInstance
    let status: InstanceStatus
    let state: ProxmoxDashboardLoadState
    let openInstance: () -> Void
    let openAPISettings: () -> Void
    let isActionInProgress: (ProxmoxResourceAction, ProxmoxResource) -> Bool
    let resourceAction: (ProxmoxResourceAction, ProxmoxResource) -> Void

    @State private var isExpanded = false
    @State private var pendingAction: PendingMenuBarResourceAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    openInstance()
                } label: {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name)
                            .font(.headline)
                        Text(status.accessibilityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .buttonStyle(.plain)

                if state.snapshot != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Hide resources" : "Show resources")
                }
            }

            if let snapshot = state.snapshot {
                MetricsStrip(metrics: snapshot.metrics)

                if isExpanded {
                    if let pendingAction {
                        MenuBarConfirmationBanner(
                            pendingAction: pendingAction,
                            cancelAction: { self.pendingAction = nil },
                            confirmAction: {
                                resourceAction(pendingAction.action, pendingAction.resource)
                                self.pendingAction = nil
                            }
                        )
                    }

                    if snapshot.resources.isEmpty {
                        Text("No VMs or LXC containers returned by the API.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(snapshot.resources) { resource in
                                    MenuBarResourceRow(
                                        resource: resource,
                                        isActionInProgress: isActionInProgress,
                                        action: {
                                            pendingAction = PendingMenuBarResourceAction(action: $0, resource: resource)
                                        }
                                    )

                                    if resource.id != snapshot.resources.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(height: resourcesListHeight(for: snapshot.resources.count))
                    }
                }
            } else if instance.hasAPIToken {
                Text(state.errorMessage ?? "Loading API metrics...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Web viewer only")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("API Settings") {
                        openAPISettings()
                    }
                    .controlSize(.small)
                    .help("Add an API token for metrics and controls")
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resourcesListHeight(for count: Int) -> CGFloat {
        min(max(CGFloat(count) * 56, 72), 300)
    }
}

private struct MenuBarConfirmationBanner: View {
    let pendingAction: PendingMenuBarResourceAction
    let cancelAction: () -> Void
    let confirmAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(pendingAction.action.title) \(pendingAction.resource.name)?")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text("Send \(pendingAction.action.title.lowercased()) to this resource.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: cancelAction)
                    .controlSize(.small)

                Spacer()

                Button(pendingAction.action.title, action: confirmAction)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(pendingAction.action == .start ? .accentColor : .red)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MenuBarResourceRow: View {
    let resource: ProxmoxResource
    let isActionInProgress: (ProxmoxResourceAction, ProxmoxResource) -> Bool
    let action: (ProxmoxResourceAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: resource.kind == .qemu ? "desktopcomputer" : "shippingbox")
                .foregroundStyle(resource.isRunning ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(resource.name)
                        .lineLimit(1)

                    Text(resource.vmid.map(String.init) ?? resource.kind.displayLabel)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }

                Text(resource.displayStatus)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(resource.isRunning ? .green : .secondary)
            }

            Spacer(minLength: 6)

            ForEach(availableActions, id: \.self) { resourceAction in
                Button {
                    action(resourceAction)
                } label: {
                    Image(systemName: resourceAction.systemImage)
                }
                .buttonStyle(.borderless)
                .disabled(isActionInProgress(resourceAction, resource))
                .help(resourceAction.title)
            }
        }
        .font(.caption)
        .padding(.vertical, 7)
    }

    private var availableActions: [ProxmoxResourceAction] {
        resource.isRunning ? [.stop, .reboot] : [.start]
    }
}

private struct PendingMenuBarResourceAction: Identifiable {
    let id = UUID()
    let action: ProxmoxResourceAction
    let resource: ProxmoxResource
}

private extension ProxmoxResource {
    var isRunning: Bool {
        status?.caseInsensitiveCompare("running") == .orderedSame
    }

    var displayStatus: String {
        guard let status, !status.isEmpty else {
            return "Unknown"
        }

        return status
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

private extension ProxmoxResource.Kind {
    var displayLabel: String {
        switch self {
        case .qemu:
            return "QEMU"
        case .lxc:
            return "LXC"
        case .storage:
            return "Storage"
        case .other:
            return "Other"
        }
    }
}
