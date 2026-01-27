---
applyTo: "Today/Models/**/*.swift"
---

# SwiftData Models Instructions

## Important Patterns

### Model Definition
- All models MUST use the `@Model` macro
- Models must be classes (not structs)
- Properties should use Swift property wrappers: `@Attribute`, `@Relationship`

### Relationships
- Use `@Relationship(deleteRule: .cascade)` for parent-child relationships where children should be deleted with parent
- Use `@Relationship(deleteRule: .nullify)` when relationship should be cleared but related objects kept
- Inverse relationships should reference each other consistently

### Schema Updates
When adding new models or modifying existing ones:
1. Add new models to the schema array in `TodayApp.swift`
2. SwiftData handles simple migrations automatically
3. For complex changes, consider migration strategy or accept data loss in development

### Current Models
- **Feed**: RSS/Reddit feed subscriptions with one-to-many relationship to Articles
- **Article**: Individual articles with metadata, read status, favorites, and optional AI summary

### Common Pitfalls
- **Don't forget cascade delete rules**: Without proper delete rules, orphaned articles may remain when feeds are deleted
- **Thread safety**: SwiftData operations should be on MainActor or in a dedicated ModelContext
- **Query predicates**: Use `#Predicate` macro for type-safe queries in views

### Example Model Structure
```swift
@Model
class ExampleModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var timestamp: Date
    
    @Relationship(deleteRule: .cascade, inverse: \RelatedModel.example)
    var relatedItems: [RelatedModel]
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.timestamp = Date()
        self.relatedItems = []
    }
}
```

### Testing Models
- Use in-memory ModelContainer for tests:
  ```swift
  let schema = Schema([Feed.self, Article.self])
  let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
  let container = try ModelContainer(for: schema, configurations: [config])
  ```
- Test relationships by creating and deleting parent objects
- Verify cascade delete behavior
