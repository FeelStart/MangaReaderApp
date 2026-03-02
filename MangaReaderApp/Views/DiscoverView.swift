import SwiftUI
import Kingfisher

/// Discover/Browse view for manga
struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var showSourcePicker = false

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.mangaList.isEmpty && !viewModel.isLoading {
                    emptyStateView
                } else {
                    mangaGridView
                }

                if viewModel.isLoading && viewModel.mangaList.isEmpty {
                    ProgressView("加载中...")
                }
            }
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    sourcePickerButton
                }
            }
            .sheet(isPresented: $showSourcePicker) {
                sourcePickerSheet
            }
            .task {
                await viewModel.discover(refresh: true)
            }
            .refreshable {
                await viewModel.discover(refresh: true)
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
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("暂无漫画")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("选择漫画源或调整筛选条件")
                .font(.body)
                .foregroundColor(.secondary)
        }
    }

    private var mangaGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.mangaList) { manga in
                    NavigationLink(destination: MangaDetailView(mangaId: manga.id, sourceId: manga.sourceId)) {
                        MangaCardView(manga: manga)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onAppear {
                        if manga == viewModel.mangaList.last {
                            Task {
                                await viewModel.loadMore()
                            }
                        }
                    }
                }

                if viewModel.isLoading && !viewModel.mangaList.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .gridCellColumns(2)
                }
            }
            .padding()
        }
    }

    private var sourcePickerButton: some View {
        Button {
            showSourcePicker = true
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.availableSources.first(where: { $0.id == viewModel.selectedSourceId })?.name ?? "选择源")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(8)
        }
    }

    private var sourcePickerSheet: some View {
        NavigationView {
            List(viewModel.availableSources) { source in
                Button {
                    Task {
                        await viewModel.changeSource(source.id)
                        showSourcePicker = false
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name)
                                .font(.headline)

                            Text(source.baseURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if source.id == viewModel.selectedSourceId {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .navigationTitle("选择漫画源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        showSourcePicker = false
                    }
                }
            }
        }
    }
}

// MARK: - Manga Card Component

struct MangaCardView: View {
    let manga: MangaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image
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
                .cornerRadius(8)
                .shadow(radius: 2)

            // Title
            Text(manga.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Metadata
            if let latest = manga.latest {
                Text(latest)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    DiscoverView()
}
