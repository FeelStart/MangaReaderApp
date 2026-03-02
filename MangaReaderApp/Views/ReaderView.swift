import SwiftUI
import Kingfisher

/// Manga reader view with vertical scrolling
struct ReaderView: View {
    let mangaId: String
    let sourceId: String
    let chapters: [Chapter]
    let startChapterIndex: Int

    @StateObject private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = false
    @State private var scrollPosition: Int?

    init(mangaId: String, sourceId: String, chapters: [Chapter], startChapterIndex: Int) {
        self.mangaId = mangaId
        self.sourceId = sourceId
        self.chapters = chapters
        self.startChapterIndex = startChapterIndex
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            mangaId: mangaId,
            sourceId: sourceId,
            chapters: chapters,
            startChapterIndex: startChapterIndex
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.images.isEmpty {
                loadingView
            } else if !viewModel.images.isEmpty {
                readerContent
            } else if viewModel.errorMessage != nil {
                errorView
            }

            if showControls {
                controlsOverlay
            }
        }
        .navigationBarHidden(true)
        .statusBar(hidden: !showControls)
        .task {
            await viewModel.loadChapter()
        }
        .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("确定") {
                viewModel.errorMessage = nil
            }
            Button("重试") {
                Task {
                    await viewModel.refresh()
                }
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Subviews

    private var readerContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.images.enumerated()), id: \.offset) { index, imageURL in
                        ZoomableImageView(url: imageURL, onTap: {
                            withAnimation {
                                showControls.toggle()
                            }
                        })
                        .id(index)
                        .onAppear {
                            viewModel.currentPage = index

                            // Prefetch upcoming images
                            viewModel.updatePrefetchForPage(index)

                            // Check if approaching last image and load next chapter
                            if index == viewModel.images.count - 3 && viewModel.hasNextChapter && !viewModel.isLoading {
                                Task {
                                    await viewModel.loadNextChapter()
                                }
                            }
                        }
                    }

                    // Loading indicator for next chapter
                    if viewModel.isLoading && !viewModel.images.isEmpty {
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)

                            Text("加载下一章...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .frame(height: 200)
                    }
                }
            }
            .scrollDisabled(false)
            .onChange(of: scrollPosition) { _, newValue in
                if let position = newValue {
                    withAnimation {
                        proxy.scrollTo(position, anchor: .top)
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text("加载中...")
                .foregroundColor(.white)
                .font(.subheadline)
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.white)

            Text("加载失败")
                .font(.title2)
                .foregroundColor(.white)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("重试") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var controlsOverlay: some View {
        VStack {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }

                Spacer()

                Text(viewModel.chapterTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)

                Spacer()

                Text(viewModel.progressText)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)
            }
            .padding()

            Spacer()
        }
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let url: URL
    let onTap: () -> Void
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        KFImage(url)
            .placeholder {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
            }
            .cacheMemoryOnly()
            .loadDiskFileSynchronously()
            .fade(duration: 0.25)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale = min(max(scale * delta, 1), 4)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        if scale < 1 {
                            withAnimation {
                                scale = 1
                            }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    if scale > 1 {
                        scale = 1
                    } else {
                        scale = 2
                    }
                }
            }
            .onTapGesture(count: 1) {
                onTap()
            }
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    let testChapter = Chapter(
        id: "1",
        mangaId: "test",
        title: "第1话",
        imageURLs: []
    )

    return ReaderView(
        mangaId: "test",
        sourceId: "copy",
        chapters: [testChapter],
        startChapterIndex: 0
    )
}
