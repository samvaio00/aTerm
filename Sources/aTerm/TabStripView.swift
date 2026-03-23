import SwiftUI
import UniformTypeIdentifiers

struct TabStripView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appModel.tabs) { tab in
                    TabButton(tab: tab)
                }

                Button {
                    appModel.createTabAndSelect(workingDirectory: appModel.selectedTab?.currentWorkingDirectory)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    appModel.openAgentPicker()
                } label: {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct TabButton: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var tab: TerminalTabViewModel

    private var isSelected: Bool {
        appModel.selectedTabID == tab.id || (appModel.selectedTabID == nil && appModel.tabs.first?.id == tab.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appModel.selectTab(id: tab.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if tab.isAgentTab {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    Text(tab.currentWorkingDirectory?.path ?? tab.statusText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(selectedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                appModel.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrag {
            NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: TabDropDelegate(currentTabID: tab.id))
    }

    private var selectedBackground: Color {
        if isSelected {
            return tab.isAgentTab ? Color.orange.opacity(0.18) : Color.accentColor.opacity(0.18)
        }
        return .clear
    }
}

private struct TabDropDelegate: DropDelegate {
    @EnvironmentObject private var appModel: AppModel
    let currentTabID: UUID

    func performDrop(info: DropInfo) -> Bool {
        true
    }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8),
                  let draggedID = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            Task { @MainActor in
                appModel.moveTab(draggedID: draggedID, targetID: currentTabID)
            }
        }
    }
}
