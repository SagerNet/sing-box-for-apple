import Runestone
import TreeSitterJSON5
import TreeSitterJSON5Queries

public extension TreeSitterLanguage {
    static var json5: TreeSitterLanguage {
        let highlightsQuery = TreeSitterLanguage.Query(contentsOf: TreeSitterJSON5Queries.Query.highlightsFileURL)
        let injectionsQuery = TreeSitterLanguage.Query(contentsOf: TreeSitterJSON5Queries.Query.injectionsFileURL)
        return TreeSitterLanguage(tree_sitter_json5(), highlightsQuery: highlightsQuery, injectionsQuery: injectionsQuery, indentationScopes: .json5)
    }
}
