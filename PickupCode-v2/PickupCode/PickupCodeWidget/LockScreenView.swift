import ActivityKit
import SwiftUI
import WidgetKit

/// 锁屏 / 通知横幅布局：大号取件码 + 驿站名 + 剩余时间 + 已取件按钮。
struct LockScreenView: View {
    let context: ActivityViewContext<PickupCodeAttributes>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.code)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(context.state.isExpiringSoon && !context.state.isCompleted ? Color.orange : Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("取件码 \(context.attributes.code)")

                Text(context.attributes.station)
                    .font(.headline)
                    .lineLimit(1)

                if let courier = context.attributes.courier, !courier.isEmpty {
                    Text(courier)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption)
                    Text(context.state.timeRemainingText)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(context.state.isExpiringSoon ? .orange : .secondary)
            }

            Spacer(minLength: 8)

            doneOrStatus
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.55))
    }

    @ViewBuilder
    private var doneOrStatus: some View {
        if context.state.isCompleted {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("已取件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .frame(width: 88)
        } else {
            if let url = URL(string: "pickupcode://done?code=\(encodedCode)") {
                Link(destination: url) {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                        Text("已取件")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 88, height: 88)
                    .background(.green.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
                }
                .simultaneousGesture(TapGesture().onEnded {
                    CompletedMarker.markCompleted(code: context.attributes.code)
                })
            }
        }
    }

    private var encodedCode: String {
        context.attributes.code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? context.attributes.code
    }
}
