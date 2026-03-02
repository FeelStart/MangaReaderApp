import SwiftUI
import Kingfisher

// MARK: - Theme Configuration

/// App theme configuration
@Observable
public class ThemeManager {
    public static let shared = ThemeManager()

    public var colorScheme: ColorScheme?
    public var themeMode: ThemeMode = .system {
        didSet {
            updateColorScheme()
        }
    }

    private init() {
        updateColorScheme()
    }

    private func updateColorScheme() {
        switch themeMode {
        case .light:
            colorScheme = .light
        case .dark:
            colorScheme = .dark
        case .system:
            colorScheme = nil
        }
    }
}

public enum ThemeMode: String, CaseIterable, Identifiable {
    case light = "浅色"
    case dark = "深色"
    case system = "跟随系统"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Main Tab View

/// Main tab navigation structure
public struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var themeManager = ThemeManager.shared

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            DiscoverView()
                .tabItem {
                    Label("发现", systemImage: "square.grid.2x2")
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(1)

            FavoritesView()
                .tabItem {
                    Label("收藏", systemImage: "heart.fill")
                }
                .tag(2)

            HistoryView()
                .tabItem {
                    Label("历史", systemImage: "clock")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .preferredColorScheme(themeManager.colorScheme)
    }
}

// MARK: - Placeholder Views

/// Favorites view
public struct FavoritesView: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "heart",
                title: "暂无收藏",
                message: "收藏的漫画会显示在这里"
            )
            .navigationTitle("收藏")
        }
    }
}

/// History view
public struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedHistory: ReadingHistory?
    @State private var showClearAlert = false

    public init() {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(
            modelContext: ModelContainerProvider.shared.modelContainer.mainContext
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("加载中...")
                } else if viewModel.historyItems.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "暂无历史",
                        message: "阅读历史会显示在这里"
                    )
                } else {
                    historyList
                }
            }
            .navigationTitle("历史")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        showClearAlert = true
                    }
                    .disabled(viewModel.historyItems.isEmpty)
                }
            }
            .task {
                viewModel.loadHistory()
            }
            .alert("清空历史", isPresented: $showClearAlert) {
                Button("取消", role: .cancel) { }
                Button("清空", role: .destructive) {
                    viewModel.clearAllHistory()
                }
            } message: {
                Text("确定要清空所有阅读历史吗？")
            }
            .fullScreenCover(item: $selectedHistory) { history in
                // Navigate to reader view
                MangaDetailView(mangaId: history.mangaId, sourceId: history.sourceId)
            }
        }
    }

    private var historyList: some View {
        List {
            ForEach(viewModel.historyItems, id: \.mangaId) { history in
                Button {
                    selectedHistory = history
                } label: {
                    HistoryRow(history: history)
                }
                .buttonStyle(PlainButtonStyle())
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteHistory(history)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

/// History row component
struct HistoryRow: View {
    let history: ReadingHistory

    var body: some View {
        HStack(spacing: 12) {
            // Cover image
            if let coverURL = history.coverURL {
                KFImage(coverURL)
                    .placeholder {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay {
                                ProgressView()
                            }
                    }
                    .resizable()
                    .aspectRatio(3/4, contentMode: .fill)
                    .frame(width: 60, height: 80)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 80)
                    .cornerRadius(8)
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundColor(.gray)
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(history.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text("读到: \(history.lastReadChapterTitle)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(formatDate(history.lastReadTime))
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}


/// Settings view
public struct SettingsView: View {
    @State private var themeManager = ThemeManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    Picker("主题模式", selection: $themeManager.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                }

                Section("缓存") {
                    NavigationLink {
                        CacheSettingsView()
                    } label: {
                        HStack {
                            Text("缓存管理")
                            Spacer()
                            Text("0 MB")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    NavigationLink("关于应用") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
}

/// Cache settings view
public struct CacheSettingsView: View {
    @State private var cacheSize: String = "计算中..."

    public init() {}

    public var body: some View {
        List {
            Section {
                HStack {
                    Text("图片缓存")
                    Spacer()
                    Text(cacheSize)
                        .foregroundColor(.secondary)
                }

                Button(role: .destructive) {
                    clearCache()
                } label: {
                    Text("清除缓存")
                }
            }

            Section {
                HStack {
                    Text("离线下载")
                    Spacer()
                    Text("0 MB")
                        .foregroundColor(.secondary)
                }

                Button(role: .destructive) {
                    // TODO: Clear downloads
                } label: {
                    Text("清除下载")
                }
            }
        }
        .navigationTitle("缓存管理")
        .task {
            await updateCacheSize()
        }
    }

    private func clearCache() {
        Task {
            await ImageCacheManager.shared.clearAllCaches()
            await updateCacheSize()
        }
    }

    private func updateCacheSize() async {
        let stats = await ImageCacheManager.shared.getCacheStatistics()
        cacheSize = stats.formattedTotalSize
    }
}

/// About view
public struct AboutView: View {
    public init() {}

    public var body: some View {
        List {
            Section {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("MangaReader")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("构建号")
                    Spacer()
                    Text("1")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Text("MangaReader 是一款高性能的 iOS 原生漫画阅读器,采用 SwiftUI + MVVM 架构构建。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("技术栈") {
                TechStackRow(title: "UI 框架", value: "SwiftUI")
                TechStackRow(title: "数据持久化", value: "SwiftData")
                TechStackRow(title: "网络层", value: "Alamofire")
                TechStackRow(title: "图片缓存", value: "Kingfisher")
                TechStackRow(title: "HTML 解析", value: "SwiftSoup")
            }
        }
        .navigationTitle("关于")
    }
}

struct TechStackRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.footnote)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
#endif
