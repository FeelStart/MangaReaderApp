import SwiftUI
import Kingfisher

/// Manga detail view
struct MangaDetailView: View {
    let mangaId: String
    let sourceId: String

    @StateObject private var viewModel: MangaDetailViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedChapter: Chapter?
    @State private var showReaderForHistory = false

    init(mangaId: String, sourceId: String) {
        self.mangaId = mangaId
        self.sourceId = sourceId
        _viewModel = StateObject(wrappedValue: MangaDetailViewModel(
            mangaId: mangaId,
            sourceId: sourceId,
            modelContext: ModelContainerProvider.shared.modelContainer.mainContext
        ))
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading && viewModel.mangaDetail == nil {
                ProgressView("加载中...")
            } else if let manga = viewModel.mangaDetail {
                mangaDetailContent(manga: manga)
            } else if viewModel.errorMessage != nil {
                errorStateView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMangaInfo()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .fullScreenCover(item: $selectedChapter) { chapter in
            if let chapterIndex = viewModel.chapters.firstIndex(where: { $0.id == chapter.id }),
               let manga = viewModel.mangaDetail {
                ReaderView(
                    mangaId: mangaId,
                    sourceId: sourceId,
                    mangaTitle: manga.title,
                    coverURL: manga.coverURL,
                    chapters: viewModel.chapters,
                    startChapterIndex: chapterIndex
                )
            }
        }
        .fullScreenCover(isPresented: $showReaderForHistory) {
            if let chapterIndex = viewModel.continueReadingChapterIndex,
               let manga = viewModel.mangaDetail {
                ReaderView(
                    mangaId: mangaId,
                    sourceId: sourceId,
                    mangaTitle: manga.title,
                    coverURL: manga.coverURL,
                    chapters: viewModel.chapters,
                    startChapterIndex: chapterIndex
                )
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func mangaDetailContent(manga: MangaDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(manga: manga)
                metadataSection(manga: manga)

                if let description = manga.description, !description.isEmpty {
                    descriptionSection(description: description)
                }

                chaptersSection
            }
            .padding()
        }
    }

    private func headerSection(manga: MangaDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Cover
            KFImage(manga.coverURL)
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                }
                .resizable()
                .aspectRatio(3/4, contentMode: .fill)
                .frame(width: 120)
                .cornerRadius(12)
                .shadow(radius: 4)

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text(manga.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(3)

                if let author = manga.author, !author.isEmpty {
                    Label(author, systemImage: "person.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                statusBadge(status: manga.status)

                if let latest = manga.latest, !latest.isEmpty {
                    Label(latest, systemImage: "book.closed.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let updateTime = manga.updateTime {
                    Label(formatDate(updateTime), systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataSection(manga: MangaDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !manga.tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("标签")
                        .font(.headline)

                    FlowLayout(spacing: 8) {
                        ForEach(manga.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .cornerRadius(12)
                        }
                    }
                }
            }

            if !manga.artists.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("画师")
                        .font(.headline)

                    Text(manga.artists.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func descriptionSection(description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介")
                .font(.headline)

            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(nil)
        }
    }

    private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("章节")
                    .font(.headline)

                Spacer()

                // Sort order toggle button
                Button {
                    viewModel.isChaptersReversed.toggle()
                } label: {
                    Image(systemName: viewModel.isChaptersReversed ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .foregroundColor(.accentColor)
                }

                Text("\(viewModel.chapters.count) 章")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Continue reading button
            if viewModel.hasReadingHistory, let history = viewModel.readingHistory {
                Button {
                    showReaderForHistory = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("继续阅读")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text("读到: \(history.lastReadChapterTitle)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }

                        Spacer()

                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if viewModel.chapters.isEmpty {
                Text("暂无章节")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.chapters.enumerated()), id: \.element.id) { index, chapter in
                        Button {
                            selectedChapter = chapter
                        } label: {
                            HStack {
                                Text(chapter.title)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color(.systemBackground))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        if index < viewModel.chapters.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    private var errorStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("加载失败")
                .font(.title2)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("重试") {
                Task {
                    await viewModel.loadMangaInfo()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helper Views

    private func statusBadge(status: MangaStatus) -> some View {
        Group {
            switch status {
            case .serial:
                Label("连载中", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(6)

            case .end:
                Label("已完结", systemImage: "checkmark.circle")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(6)

            case .unknown:
                EmptyView()
            }
        }
    }

    // MARK: - Helper Methods

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for size in sizes {
            if lineWidth + size.width > proposal.width ?? 0 {
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            totalWidth = max(totalWidth, lineWidth)
        }

        totalHeight += lineHeight

        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var lineX = bounds.minX
        var lineY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if lineX + size.width > bounds.maxX && lineX > bounds.minX {
                lineY += lineHeight + spacing
                lineHeight = 0
                lineX = bounds.minX
            }

            subview.place(
                at: CGPoint(x: lineX, y: lineY),
                proposal: ProposedViewSize(size)
            )

            lineHeight = max(lineHeight, size.height)
            lineX += size.width + spacing
        }
    }
}

#Preview {
    NavigationView {
        MangaDetailView(mangaId: "test", sourceId: "dmzj")
    }
}
