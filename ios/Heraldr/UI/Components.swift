import SwiftUI

struct Wallpaper: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Color.wallBase
                Circle().fill(Color.wallBlobOne)
                    .frame(width: width * 0.8)
                    .position(x: width * 0.1, y: height * 0.22)
                Circle().fill(Color.wallBlobTwo)
                    .frame(width: width * 0.9)
                    .position(x: width * 0.95, y: height * 0.55)
                Circle().fill(Color.wallBlobThree)
                    .frame(width: width * 0.75)
                    .position(x: width * 0.3, y: height * 0.98)
            }
            .blur(radius: 60)
            .opacity(0.9)
        }
        .ignoresSafeArea()
    }
}

struct StatusDot: View {
    let status: AgentStatus
    var size: CGFloat = 10
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .background {
                if status == .working {
                    Circle()
                        .stroke(status.color.opacity(pulsing ? 0 : 0.7), lineWidth: pulsing ? 9 : 0)
                        .scaleEffect(pulsing ? 1.9 : 1)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)
                        .onAppear { pulsing = true }
                } else if status == .blocked {
                    Circle().fill(status.color.opacity(0.3)).padding(-3)
                }
            }
            .accessibilityLabel(status.label)
    }
}

struct WaitBadge: View {
    var compact = false

    var body: some View {
        Label("en attente", systemImage: "clock")
            .font(.system(size: compact ? 10 : 12, weight: .bold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(AgentStatus.working.color.opacity(0.18), in: .capsule)
            .foregroundStyle(AgentStatus.working.color)
    }
}

struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        Image("Logo")
            .resizable()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.23, style: .continuous))
    }
}

struct NoticeToast: View {
    let notice: AppModel.Notice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.onAccent)
                .frame(width: 36, height: 36)
                .background(color, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.subheadline.bold())
                Text(notice.detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var icon: String {
        switch notice.kind {
        case .sent: "paperplane.fill"
        case .queued: "clock"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch notice.kind {
        case .sent: AgentStatus.done.color
        case .queued: AgentStatus.working.color
        case .failed: AgentStatus.blocked.color
        }
    }
}
