import Runestone

public extension TreeSitterIndentationScopes {
    static var json5: TreeSitterIndentationScopes {
        TreeSitterIndentationScopes(indent: ["object", "array"], outdent: ["}", "]"])
    }
}
