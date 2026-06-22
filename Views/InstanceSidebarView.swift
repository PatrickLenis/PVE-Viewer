import SwiftUI

struct InstanceSidebarView: View {
    let instances: [ProxmoxInstance]
    let statuses: [ProxmoxInstance.ID: InstanceStatus]
    let dashboardStates: [ProxmoxInstance.ID: ProxmoxDashboardLoadState]
    @Binding var selection: ProxmoxInstance.ID?

    let addAction: () -> Void
    let editAction: (ProxmoxInstance) -> Void
    let deleteAction: (ProxmoxInstance) -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Instances") {
                ForEach(instances) { instance in
                    InstanceRow(
                        instance: instance,
                        status: statuses[instance.id] ?? .unknown,
                        dashboardState: dashboardStates[instance.id] ?? .idle
                    )
                    .tag(instance.id)
                    .contextMenu {
                        Button("Edit") { editAction(instance) }
                        Button("Delete", role: .destructive) { deleteAction(instance) }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
        .navigationTitle("Proxmox")
    }

    private var sidebarFooter: some View {
        HStack {
            Button(action: addAction) {
                Label("Add Instance", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .buttonStyle(.borderless)
            .help("Add a Proxmox instance")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct InstanceRow: View {
    let instance: ProxmoxInstance
    let status: InstanceStatus
    let dashboardState: ProxmoxDashboardLoadState
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .shadow(color: status.color.opacity(status == .online || status == .tlsWarning ? 0.45 : 0), radius: 4)
                .accessibilityLabel(status.accessibilityLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(instance.url.host ?? instance.url.absoluteString)
                        .lineLimit(1)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(status.sidebarLabel)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if instance.hasAPIToken {
                    sidebarMetrics
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.proxmoxOrange.opacity(0.08) : .clear)
        }
        .animation(.easeOut(duration: 0.16), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: status)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var sidebarMetrics: some View {
        if let metrics = dashboardState.snapshot?.metrics {
            HStack(spacing: 8) {
                SidebarMetricLabel(title: "CPU", value: metrics.cpuUsage)
                SidebarMetricLabel(title: "RAM", value: metrics.memoryUsage)
                SidebarMetricLabel(title: "Disk", value: metrics.storageUsage)
            }
            .padding(.top, 2)
        } else {
            Text(dashboardState.errorMessage ?? "API metrics pending")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private extension InstanceStatus {
    var sidebarLabel: String {
        switch self {
        case .unknown:
            return "Checking"
        case .offline:
            return "Offline"
        case .tlsWarning:
            return "TLS warning"
        case .error:
            return "Error"
        case .online:
            return "Connected"
        }
    }
}

private struct SidebarMetricLabel: View {
    let title: String
    let value: Double?

    var body: some View {
        Text("\(title) \(formattedValue)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var formattedValue: String {
        guard let value else { return "--" }
        return Self.formatter.string(from: NSNumber(value: value)) ?? "--"
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
