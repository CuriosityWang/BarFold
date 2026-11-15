import AppKit
import SwiftUI

struct MenuBarOrderHelp: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("调整菜单栏顺序").font(.title3.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭引导")
                .help("关闭引导")
            }
            Text("按住 ⌘ 拖动菜单栏图标调整顺序")
                .font(.system(size: 16))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 11) {
                glyph("shield")
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.tint)
                    Image(systemName: "envelope")
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
                        }
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(alignment: .top, spacing: 0) {
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 19))
                        Text("⌘")
                            .font(.system(size: 13, weight: .medium))
                            .padding(3)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
                            }
                            .offset(y: 12)
                    }
                    .offset(x: 18, y: 12)
                }
                glyph("cloud")
                Divider().frame(height: 20)
                Image(systemName: "chevron.right").font(.system(size: 17, weight: .medium))
                Divider().frame(height: 20)
                glyph("calendar")
                glyph("wifi")
                glyph("battery.100percent")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35))
            }
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("示意：按住 Command 键，将箭头左侧的图标向左拖动")
            .allowsHitTesting(false)
        }
        .padding(20)
        .frame(width: 400)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 18)).frame(width: 24)
    }
}
