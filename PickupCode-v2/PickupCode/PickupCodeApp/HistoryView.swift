import SwiftUI

/// 历史记录列表：左滑删除、复制取件码、标记已取件、清空已完结。
struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        Group {
            if history.records.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        List {
            let active = history.activeRecords
            let finished = history.records.filter { $0.isCompleted || $0.isExpired }

            if !active.isEmpty {
                Section("进行中") {
                    ForEach(active) { record in
                        row(record)
                    }
                }
            }

            Section {
                ForEach(finished) { record in
                    row(record)
                }
            } header: {
                if finished.isEmpty {
                    Text("暂无已完结记录")
                } else {
                    Text("已完结")
                }
            } footer: {
                if !finished.isEmpty {
                    Button(role: .destructive) {
                        history.clearCompleted()
                    } label: {
                        Text("清空已完结记录")
                    }
                }
            }
        }
    }

    private func row(_ record: PickupCode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.isCompleted ? "checkmark.circle.fill" : (record.isExpired ? "clock.badge.exclamationmark" : "shippingbox.fill"))
                .foregroundStyle(record.isCompleted ? .green : (record.isExpired ? .orange : .accentColor))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.code)
                        .font(.title3.weight(.bold).monospaced())

                    Text(record.statusText)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background( capsuleBackground(for: record))
                }

                Text(record.station)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) 收到")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            if !record.isCompleted && !record.isExpired {
                Button {
                    UIPasteboard.general.string = record.code
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("复制取件码 \(record.code)")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                history.deleteRecord(id: record.id)
            } label: {
                Label("删除", systemImage: "trash")
            }

            if !record.isCompleted && !record.isExpired {
                Button {
                    history.markCompleted(code: record.code)
                    Task {
                        try? await LiveActivityManager.shared.endActivity(code: record.code)
                    }
                } label: {
                    Label("已取件", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
        }
    }

    private func capsuleBackground(for record: PickupCode) -> some ShapeStyle {
        if record.isCompleted { return Color.green.opacity(0.15) }
        if record.isExpired { return Color.orange.opacity(0.15) }
        return Color.accentColor.opacity(0.12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("暂无历史记录")
                .font(.headline)
            Text("收到快递取件短信后会自动出现在这里")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        HistoryView()
            .environmentObject(HistoryStore.shared)
    }
}
