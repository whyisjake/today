import SwiftUI
import SwiftData

#if os(iOS)
/// A paging container that renders articles in a TabView(.page) for train-car style swiping.
/// Preloads adjacent Reddit post data for instant transitions.
struct ArticlePagerView: View {
    let context: [PersistentIdentifier]
    let initialArticleID: PersistentIdentifier

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex: Int
    private let postCache = RedditPostCache.shared

    init(context: [PersistentIdentifier], initialArticleID: PersistentIdentifier) {
        self.context = context
        self.initialArticleID = initialArticleID
        self._currentIndex = State(initialValue: context.firstIndex(of: initialArticleID) ?? 0)
    }

    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(context.enumerated()), id: \.element) { index, articleID in
                if let article = modelContext.model(for: articleID) as? Article {
                    articleView(for: article, at: index)
                        .tag(index)
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: currentIndex) { _, newIndex in
            preloadAdjacent(around: newIndex)
        }
        .onAppear {
            preloadAdjacent(around: currentIndex)
        }
    }

    @ViewBuilder
    private func articleView(for article: Article, at index: Int) -> some View {
        let previousID = index > 0 ? context[index - 1] : nil
        let nextID = index < context.count - 1 ? context[index + 1] : nil

        if article.isRedditPost {
            let cached = postCache.get(for: article.persistentModelID)
            RedditPostView(
                article: article,
                previousArticleID: previousID,
                nextArticleID: nextID,
                onNavigateToPrevious: { _ in
                    withAnimation { currentIndex = index - 1 }
                },
                onNavigateToNext: { _ in
                    withAnimation { currentIndex = index + 1 }
                },
                cachedPost: cached?.post,
                cachedComments: cached?.comments
            )
        } else {
            ArticleDetailSimple(
                article: article,
                previousArticleID: previousID,
                nextArticleID: nextID,
                onNavigateToPrevious: { _ in
                    withAnimation { currentIndex = index - 1 }
                },
                onNavigateToNext: { _ in
                    withAnimation { currentIndex = index + 1 }
                }
            )
        }
    }

    private func preloadAdjacent(around index: Int) {
        // Preload ±2 articles for Reddit posts
        let window = max(0, index - 2)...min(context.count - 1, index + 2)
        let windowIDs = Set(window.map { context[$0] })

        // Evict articles outside the window
        postCache.evict(keeping: windowIDs)

        // Preload adjacent Reddit articles
        for i in window where i != index {
            let articleID = context[i]
            if let article = modelContext.model(for: articleID) as? Article,
               article.isRedditPost {
                postCache.preload(article: article)
            }
        }
    }
}
#endif
