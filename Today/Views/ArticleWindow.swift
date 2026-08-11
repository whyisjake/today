//
//  ArticleWindow.swift
//  Today
//
//  Owns a bounded @Query so the fetched window can follow view state.
//
//  Why this exists: @Query builds its descriptor in `init`, so it cannot read @State from
//  the view that declares it. TodayView's window depends on `daysToLoad` and the selected
//  category, both of which are @State. Wrapping the query in a child view whose init takes
//  those values means SwiftUI re-initialises it — and therefore re-runs the fetch with a new
//  descriptor — whenever they change, while the parent keeps ownership of the state.
//
//  The alternative (fetching manually in a computed property) would lose @Query
//  reactivity, so newly synced articles would not appear until something else forced a
//  redraw.
//

import SwiftUI
import SwiftData

struct ArticleWindow<Content: View>: View {
    @Query private var articles: [Article]
    private let content: ([Article]) -> Content

    init(
        daysToLoad: Int,
        selection: ArticleSelection,
        @ViewBuilder content: @escaping ([Article]) -> Content
    ) {
        _articles = Query(ArticleQuery.windowDescriptor(
            daysToLoad: daysToLoad,
            selection: ArticleQuery.descriptorSelection(for: selection)
        ))
        self.content = content
    }

    var body: some View {
        content(articles)
    }
}
