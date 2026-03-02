import SwiftUI
import Kingfisher

/// Search view for manga
struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var showSourcePicker = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar

                ZStack {
                    if viewModel.searchResults.isEmpty && !viewModel.isSearching {
                        emptyStateView
                    } else {
                        searchResultsView
                    }

                    if viewModel.isSearching && viewModel.searchResults.isEmpty {
                        ProgressView("搜索中...")
                    }
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    sourcePickerButton
                }
            }
            .sheet(isPresented: $showSourcePicker) {
                sourcePickerSheet
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

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("搜索漫画...", text: $viewModel.searchText)
                .focused($isSearchFieldFocused)
                .textFieldStyle(PlainTextFieldStyle())
                .submitLabel(.search)
                .onSubmit {
                    Task {
                        await viewModel.search(refresh: true)
                    }
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    viewModel.searchResults.removeAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel.searchText.isEmpty ? "magnifyingglass" : "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(viewModel.searchText.isEmpty ? "输入关键词搜索" : "未找到相关漫画")
                .font(.title2)
                .foregroundColor(.secondary)

            if !viewModel.searchText.isEmpty {
                Text("尝试使用不同的关键词或选择其他漫画源")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private var searchResultsView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.searchResults) { manga in
                    NavigationLink(destination: MangaDetailView(mangaId: manga.id, sourceId: manga.sourceId)) {
                        MangaCardView(manga: manga)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onAppear {
                        if manga == viewModel.searchResults.last {
                            Task {
                                await viewModel.loadMore()
                            }
                        }
                    }
                }

                if viewModel.isSearching && !viewModel.searchResults.isEmpty {
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

#Preview {
    SearchView()
}
