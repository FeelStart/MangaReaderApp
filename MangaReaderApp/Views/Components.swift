import SwiftUI

// MARK: - Loading View

/// Generic loading view with spinner and optional message
public struct LoadingView: View {
    let message: String?

    public init(message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error View

/// Generic error view with icon, message, and retry button
public struct ErrorView: View {
    let error: Error
    let retryAction: (() -> Void)?

    public init(error: Error, retryAction: (() -> Void)? = nil) {
        self.error = error
        self.retryAction = retryAction
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("出错了")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let retryAction = retryAction {
                Button(action: retryAction) {
                    Label("重试", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View

/// Generic empty state view
public struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let action: (() -> Void)?
    let actionTitle: String?

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Manga Card View

/// Reusable manga card component
public struct MangaCard: View {
    let manga: MangaItem
    let onTap: () -> Void

    public init(manga: MangaItem, onTap: @escaping () -> Void) {
        self.manga = manga
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Cover image
                if let coverURL = manga.coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .aspectRatio(3/4, contentMode: .fit)
                                .overlay {
                                    ProgressView()
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .aspectRatio(3/4, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(3/4, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Title
                Text(manga.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Latest chapter
                if let latest = manga.latest {
                    Text(latest)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Bar

/// Custom search bar component
public struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    let onSearch: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String = "搜索漫画",
        onSearch: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onSearch = onSearch
    }

    public var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .onSubmit(onSearch)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Skeleton Loading

/// Skeleton loading placeholder
public struct SkeletonView: View {
    @State private var isAnimating = false

    public var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .overlay {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.4), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.3)
                        .offset(x: isAnimating ? geometry.size.width : -geometry.size.width * 0.3)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Grid Skeleton

public struct MangaGridSkeleton: View {
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)
    ]

    public init() {}

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonView()
                        .aspectRatio(3/4, contentMode: .fit)

                    SkeletonView()
                        .frame(height: 12)

                    SkeletonView()
                        .frame(height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(width: 80)
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct ComponentPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            LoadingView(message: "加载中...")
                .previewDisplayName("Loading")

            ErrorView(
                error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "网络连接失败"]),
                retryAction: {}
            )
            .previewDisplayName("Error")

            EmptyStateView(
                icon: "book",
                title: "暂无收藏",
                message: "收藏的漫画会显示在这里",
                actionTitle: "去发现",
                action: {}
            )
            .previewDisplayName("Empty State")

            MangaGridSkeleton()
                .previewDisplayName("Skeleton")
        }
    }
}
#endif
