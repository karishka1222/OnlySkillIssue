import Foundation

public final class ASTOptimizer {
    /// Main entry point: optimize a list of nodes (program)
    public static func optimizeProgram(_ nodes: [Node]) -> [Node] {
        // First, recursively optimize nodes (constant folding inside expressions)
        var optimizedNodes = nodes.map { optimizeNode($0) }
        // Then remove unused variables (dead setq elimination)
        optimizedNodes = removeUnusedVariables(optimizedNodes)
        return optimizedNodes
    }

    /// Simplifies a single node
    private static func optimizeNode(_ node: Node) -> Node {
        let e = optimizeElement(node.element)
        return Node(element: e, line: node.line)
    }

    /// Recursive optimization of an element
    private static func optimizeElement(_ e: Element) -> Element {
        switch e {
        case .list(let elems):
            // Recursively optimize children
            let optimizedChildren = elems.map { optimizeElement($0) }

            // Attempt constant folding
            if let folded = constantFold(optimizedChildren) {
                return folded
            }
            return .list(optimizedChildren)
        default:
            return e
        }
    }

    /// Simple constant folding
    private static func constantFold(_ elems: [Element]) -> Element? {
        guard elems.count >= 1 else { return nil }
        guard case .atom(let opName) = elems[0] else { return nil }

        // Normalize operator name
        let op = opName

        // Arithmetic operations (binary)
        let addNames = ["+", "plus"]
        let subNames = ["-", "minus"]
        let mulNames = ["*", "times"]
        let divNames = ["/", "divide"]

        if (addNames + subNames + mulNames + divNames).contains(op),
           elems.count == 3,
           let lhs = numericValue(of: elems[1]),
           let rhs = numericValue(of: elems[2]) {
            if addNames.contains(op) {
                let sum = lhs + rhs
                if floor(sum) == sum { return .integer(Int(sum)) }
                return .real(sum)
            }
            if subNames.contains(op) {
                let res = lhs - rhs
                if floor(res) == res { return .integer(Int(res)) }
                return .real(res)
            }
            if mulNames.contains(op) {
                let res = lhs * rhs
                if floor(res) == res { return .integer(Int(res)) }
                return .real(res)
            }
            if divNames.contains(op) {
                if rhs == 0 { return nil } // avoid division by zero
                let res = lhs / rhs
                if floor(res) == res { return .integer(Int(res)) }
                return .real(res)
            }
        }

        // Comparison operations
        let lessNames = ["<", "less"]
        let leNames   = ["<=", "lesseq"]
        let greaterNames = [">", "greater"]
        let geNames = [">=", "greatereq"]
        let eqNames = ["=", "==", "equal"]
        let neqNames = ["nonequal"]

        if (lessNames + leNames + greaterNames + geNames + eqNames + neqNames).contains(op),
           elems.count == 3,
           let lhs = numericValue(of: elems[1]),
           let rhs = numericValue(of: elems[2]) {
            if lessNames.contains(op) { return .boolean(lhs < rhs) }
            if leNames.contains(op)   { return .boolean(lhs <= rhs) }
            if greaterNames.contains(op) { return .boolean(lhs > rhs) }
            if geNames.contains(op)   { return .boolean(lhs >= rhs) }
            if eqNames.contains(op)   { return .boolean(lhs == rhs) }
            if neqNames.contains(op)  { return .boolean(lhs != rhs) }
        }

        // Logical operations
        if op == "not", elems.count == 2 {
            if case .boolean(let b) = elems[1] { return .boolean(!b) }
        }
        if op == "and", elems.count == 3 {
            if case .boolean(let a) = elems[1], case .boolean(let b) = elems[2] {
                return .boolean(a && b)
            }
        }
        if op == "or", elems.count == 3 {
            if case .boolean(let a) = elems[1], case .boolean(let b) = elems[2] {
                return .boolean(a || b)
            }
        }

        return nil
    }

    /// Converts element to numeric value (integer, real, boolean as 1/0)
    private static func numericValue(of e: Element) -> Double? {
        switch e {
        case .integer(let i): return Double(i)
        case .real(let r): return r
        case .boolean(let b): return b ? 1.0 : 0.0
        default: return nil
        }
    }

    // MARK: - Remove Unused Variables
    private static func removeUnusedVariables(_ nodes: [Node]) -> [Node] {
        var declared: Set<String> = []
        var used: Set<String> = []

        func collect(element: Element) {
            switch element {
            case .atom(let s):
                used.insert(s)

            case .list(let elems):
                if elems.count >= 3,
                   case .atom("setq") = elems[0],
                   case .atom(let varName) = elems[1] {

                    declared.insert(varName)
                    collect(element: elems[2]) // collect inside RHS

                } else {
                    elems.forEach { collect(element: $0) }
                }

            default: break
            }
        }

        // First pass: find declared + used
        for n in nodes { collect(element: n.element) }

        let unused = declared.subtracting(used)
        guard !unused.isEmpty else { return nodes }

        // Second pass: replace unused setq with its function call (value)
        let optimized = nodes.compactMap { node -> Node? in
            guard case .list(let elems) = node.element,
                  elems.count >= 3,
                  case .atom("setq") = elems[0],
                  case .atom(let varName) = elems[1]
            else {
                return node // keep unchanged
            }

            if unused.contains(varName) {
                let value = elems[2]
                return Node(element: value, line: node.line)
            }

            return node
        }

        return optimized
    }
}
