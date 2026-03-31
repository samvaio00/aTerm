import SwiftUI

struct ThemeCard: View {
    let theme: TerminalTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(theme.palette.background.nsColor))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("$ git status")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        Text("clean")
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(theme.palette.ansi[10].nsColor))
                    }
                    .foregroundStyle(Color(theme.palette.foreground.nsColor))
                    .padding(8)
                }
                .frame(height: 72)

            Text(theme.name)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct ThemeCatalogSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var catalog = ThemeCatalog()
    @State private var searchText = ""
    @State private var downloadingID: String?
    @Environment(\.dismiss) private var dismiss

    private var filteredEntries: [ThemeCatalog.CatalogEntry] {
        if searchText.isEmpty { return catalog.entries }
        return catalog.entries.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Theme Catalog")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            TextField("Search themes...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if catalog.isLoading {
                Spacer()
                ProgressView("Loading catalog...")
                Spacer()
            } else if let error = catalog.errorMessage {
                Spacer()
                Text(error)
                    .foregroundStyle(.red)
                    .padding()
                Spacer()
            } else {
                List(filteredEntries) { entry in
                    HStack {
                        Text(entry.name)
                        Spacer()
                        if entry.isDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if downloadingID == entry.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Download") {
                                downloadingID = entry.id
                                Task {
                                    do {
                                        let url = try await catalog.download(entry)
                                        try appModel.importTheme(from: url)
                                    } catch {
                                        // Theme download/import failed silently
                                    }
                                    downloadingID = nil
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .frame(width: 480, height: 520)
        .task {
            let existingIDs = Set(appModel.allThemes.map(\.id))
            await catalog.fetchIndex(existingThemeIDs: existingIDs)
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
        .font(.system(size: 12, weight: .medium))
    }

    private var formattedValue: String {
        if step >= 1 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }
}
