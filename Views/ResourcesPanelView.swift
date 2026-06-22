import SwiftUI

struct ResourcesPanelView: View {
    let state: ProxmoxDashboardLoadState
    let instance: ProxmoxInstance
    let collapseAction: () -> Void
    let isActionInProgress: (ProxmoxResourceAction, ProxmoxResource) -> Bool
    let refreshAction: () -> Void
    let resourceAction: (ProxmoxResourceAction, ProxmoxResource) -> Void

    @State private var pendingAction: PendingResourceAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Resources", systemImage: "list.bullet.rectangle")
                    .font(.headline)

                Spacer()

                Button(action: collapseAction) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Collapse resources")

                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh API resources")
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.action.title, role: pendingAction.action == .start ? nil : .destructive) {
                    resourceAction(pendingAction.action, pendingAction.resource)
                    self.pendingAction = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let pendingAction {
                Text("Send \(pendingAction.action.title.lowercased()) to \(pendingAction.resource.name)?")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            PlaceholderPanelText("API metrics will appear after the first refresh.")
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading Proxmox resources...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
        case .failed(let message):
            PlaceholderPanelText(message)
        case .loaded(let snapshot):
            VStack(alignment: .leading, spacing: 10) {
                MetricsStrip(metrics: snapshot.metrics)

                if snapshot.resources.isEmpty {
                    PlaceholderPanelText("No VMs or LXC containers returned by the API.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(snapshot.resources) { resource in
                                ResourceRow(
                                    resource: resource,
                                    isActionInProgress: isActionInProgress,
                                    action: { pendingAction = PendingResourceAction(action: $0, resource: resource) }
                                )
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var confirmationTitle: String {
        guard let pendingAction else { return "Confirm Action" }
        return "\(pendingAction.action.title) \(pendingAction.resource.name)?"
    }
}

struct MetricsStrip: View {
    let metrics: ProxmoxClusterMetrics

    var body: some View {
        HStack(spacing: 18) {
            MetricPill(title: "CPU", value: metrics.cpuUsage, systemImage: "cpu")
            MetricPill(title: "RAM", value: metrics.memoryUsage, systemImage: "memorychip")
            MetricPill(title: "Storage", value: metrics.storageUsage, systemImage: "internaldrive")
        }
    }
}

struct MetricPill: View {
    let title: String
    let value: Double?
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(formattedValue)
                .fontWeight(.semibold)
        }
        .font(.caption)
    }

    private var formattedValue: String {
        guard let value else { return "--" }
        return Self.percentFormatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct ResourceRow: View {
    let resource: ProxmoxResource
    let isActionInProgress: (ProxmoxResourceAction, ProxmoxResource) -> Bool
    let action: (ProxmoxResourceAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: resource.kind == .qemu ? "desktopcomputer" : "shippingbox")
                .foregroundStyle(resource.status == "running" ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(resource.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(resource.vmid.map(String.init) ?? resource.kind.displayLabel)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }

                HStack(spacing: 10) {
                    Text(resource.displayStatus)
                        .foregroundStyle(resource.status == "running" ? .green : .secondary)
                    MetricInline(systemImage: "cpu", value: resource.cpu)
                    MetricInline(systemImage: "memorychip", value: fraction(resource.mem, resource.maxmem))
                    MetricInline(systemImage: "internaldrive", value: fraction(resource.disk, resource.maxdisk))
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

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
        .padding(.vertical, 8)
    }

    private var availableActions: [ProxmoxResourceAction] {
        resource.isRunning ? [.stop, .reboot] : [.start]
    }

    private func fraction(_ used: Double?, _ max: Double?) -> Double? {
        guard let used, let max, max > 0 else { return nil }
        return used / max
    }
}

private struct MetricInline: View {
    let systemImage: String
    let value: Double?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(formattedValue)
        }
        .foregroundStyle(.secondary)
    }

    private var formattedValue: String {
        guard let value else { return "--" }
        return Self.percentFormatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct PlaceholderPanelText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 92)
    }
}

private struct PendingResourceAction: Identifiable {
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
