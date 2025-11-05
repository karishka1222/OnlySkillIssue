import Foundation

// MARK: - Semantic Error
public struct SemanticError: Error, CustomStringConvertible {
    public let message: String
    public let line: Int
    public var description: String {
        "Line \(line): Semantic error: \(message)"
    }
}

public enum TypeKind: Equatable, CustomStringConvertible {
    case number  // combines integer and real as in specification
    case bool
    case any
    case null
    case list    // type for lists

    public var description: String {
        switch self {
        case .number: return "number"
        case .bool: return "bool"
        case .any: return "any"
        case .null: return "null"
        case .list: return "list"
        }
    }
}

// MARK: - SymbolTable
public final class SymbolTable {
    private var variables: [String: TypeKind] = [:]
    private var functions: [String: ([String], Element)] = [:]
    private weak var parent: SymbolTable?

    public init(parent: SymbolTable? = nil) {
        self.parent = parent
    }

    public func defineVariable(_ name: String, type: TypeKind = .any) {
        variables[name] = type
    }

    public func isVariableDefined(_ name: String) -> Bool {
        return lookupVariableType(name) != nil
    }

    public func lookupVariableType(_ name: String) -> TypeKind? {
        var cur: SymbolTable? = self
        var visited = Set<ObjectIdentifier>()
        while let table = cur {
            let id = ObjectIdentifier(table)
            if visited.contains(id) { return nil }
            visited.insert(id)
            if let t = table.variables[name] { return t }
            cur = table.parent
        }
        return nil
    }

    public func defineFunction(_ name: String, params: [String], body: Element) {
        functions[name] = (params, body)
    }

    public func lookupFunction(_ name: String) -> ([String], Element)? {
        var cur: SymbolTable? = self
        var visited = Set<ObjectIdentifier>()
        while let table = cur {
            let id = ObjectIdentifier(table)
            if visited.contains(id) { return nil }
            visited.insert(id)
            if let fn = table.functions[name] { return fn }
            cur = table.parent
        }
        return nil
    }
}

// MARK: - SemanticAnalyzer
public final class SemanticAnalyzer {
    private let ast: [Node]
    private var errors: [SemanticError] = []
    private let globalScope = SymbolTable()

    public init(ast: [Node]) {
        self.ast = ast
    }

    public func analyze() -> [SemanticError] {
        for node in ast {
            analyzeNode(node.element, in: globalScope, line: node.line, inProg: false, inWhile: false, inFunc: false)
        }
        return errors
    }

    // MARK: - Analyze Node
    private func analyzeNode(_ element: Element, in scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool, inFunc: Bool) {
        switch element {
        case .atom(let name):
            if !Self.isBuiltinSymbol(name) && !scope.isVariableDefined(name) && scope.lookupFunction(name) == nil {
                recordError("Undeclared identifier '\(name)'", line)
            }

        case .list(let elements):
            // Skip analysis for quote
            if let first = elements.first, case .atom(let head) = first, head == "quote" {
                checkQuote(elements, line: line)
                return
            }

            guard let first = elements.first else { return }

            // Anonymous lambda call ((lambda (...) body) args...)
            if case .list(let inner) = first,
               let innerFirst = inner.first,
               case .atom(let innerHead) = innerFirst,
               innerHead == "lambda" {
                handleAnonymousLambdaCall(innerLambda: inner, callArgs: Array(elements.dropFirst()), parentScope: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
                return
            }

            if case .atom(let head) = first {
                switch head {
                case "setq":
                    checkSetq(elements, scope: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
                case "func":
                    checkFunc(elements, scope: scope, line: line)
                case "lambda":
                    checkLambda(elements, scope: scope, line: line)
                case "prog":
                    checkProg(elements, scope: scope, line: line)
                case "cond":
                    checkCond(elements, scope: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
                case "while":
                    checkWhile(elements, scope: scope, line: line, inProg: inProg, inFunc: inFunc)
                case "return":
                    checkReturn(elements, scope: scope, line: line, inProg: inProg, inFunc: inFunc)
                case "break":
                    if !inWhile {
                        recordError("break used outside of while", line)
                    }
                default:
                    checkFunctionCall(elements, scope: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
                }
            } else {
                // First element is not an atom, it may be a valid expression
                for elem in elements {
                    analyzeNode(elem, in: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
                }
            }
        case .integer, .real, .boolean, .null:
            break // literals do not require analysis
        }
    }

    // MARK: - Builtin specifications
    private struct BuiltinSpec {
        let arity: Int
        let expectedArgTypes: [TypeKind]?
        let returnType: TypeKind?
    }

    private let builtinSpecs: [String: BuiltinSpec] = [
        // Arithmetic functions
        "plus":   BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),
        "minus":  BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),
        "times":  BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),
        "divide": BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),

        // Comparisons
        "less": BuiltinSpec(arity: 2, expectedArgTypes: [.any, .any], returnType: .bool),
        "lesseq": BuiltinSpec(arity: 2, expectedArgTypes: [.any, .any], returnType: .bool),
        "greater": BuiltinSpec(arity: 2, expectedArgTypes: [.any, .any], returnType: .bool),
        "greatereq": BuiltinSpec(arity: 2, expectedArgTypes: [.any, .any], returnType: .bool),
        "equal": BuiltinSpec(arity: 2, expectedArgTypes: nil, returnType: .bool),
        "nonequal": BuiltinSpec(arity: 2, expectedArgTypes: nil, returnType: .bool),

        // List operations
        "head": BuiltinSpec(arity: 1, expectedArgTypes: [.list], returnType: .any),
        "tail": BuiltinSpec(arity: 1, expectedArgTypes: [.list], returnType: .list),
        "cons": BuiltinSpec(arity: 2, expectedArgTypes: [.any, .list], returnType: .list),

        // Logical operators
        "and": BuiltinSpec(arity: 2, expectedArgTypes: [.bool, .bool], returnType: .bool),
        "or": BuiltinSpec(arity: 2, expectedArgTypes: [.bool, .bool], returnType: .bool),
        "xor": BuiltinSpec(arity: 2, expectedArgTypes: [.bool, .bool], returnType: .bool),
        "not": BuiltinSpec(arity: 1, expectedArgTypes: [.bool], returnType: .bool),

        // Predicates
        "isint": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "isreal": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "isbool": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "isatom": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "islist": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "isnull": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),

        // Evaluator
        "eval": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .any)
    ]

    // MARK: - Type Inference
    private func inferType(of element: Element, in scope: SymbolTable? = nil, depth: Int = 0) -> TypeKind {
        if depth > 10 { return .any } // prevent infinite recursion

        switch element {
        case .integer, .real:
            return .number
        case .boolean:
            return .bool
        case .null:
            return .null
        case .atom(let name):
            if let s = scope, let t = s.lookupVariableType(name) { return t }
            return .any
        case .list(let elems):
            if let first = elems.first, case .atom("quote") = first {
                return .list
            }
            
            guard let first = elems.first else { return .list }

            if case .atom(let head) = first {
                switch head {
                case "quote":
                    return .list
                case "setq", "func", "lambda", "prog", "cond", "while", "return", "break":
                    return .any
                default:
                    if let spec = builtinSpecs[head] {
                        return spec.returnType ?? .any
                    }
                    if let _ = scope?.lookupFunction(head) {
                        return .any
                    }
                }
            }
            return .any
        }
    }

    // MARK: - Builtin Call Checks
    private func checkBuiltinCall(_ name: String, args: [Element], in scope: SymbolTable, line: Int) {
        guard let spec = builtinSpecs[name] else { return }

        if args.count != spec.arity {
            recordError("\(name) expects \(spec.arity) argument(s), got \(args.count)", line)
        }
        
        if ["less", "lesseq", "greater", "greatereq"].contains(name) {
            for (idx, arg) in args.enumerated() {
                let t = inferType(of: arg, in: scope)
                if t != .number && t != .bool && t != .any {
                    recordError("\(name) expects number or bool for argument \(idx+1), got \(t)", line)
                }
            }
            return
        }
        
        if ["equal", "nonequal"].contains(name) {
            let allowed: [TypeKind] = [.number, .bool]
            let types = args.map { inferType(of: $0, in: scope) }
            if types.contains(where: { !allowed.contains($0) && $0 != .any }) {
                recordError("\(name) expects integer, real, or bool arguments", line)
            }
            return
        }
        
        if name == "eval", args.count == 1 {
            let arg = args[0]
            if case .list(let inner) = arg, let first = inner.first, case .atom("quote") = first {
                if inner.count == 2, case .list(let quotedExpr) = inner[1] {
                    analyzeNode(.list(quotedExpr), in: scope, line: line, inProg: false, inWhile: false, inFunc: false)
                }
            }
            return
        }

        if let expectedTypes = spec.expectedArgTypes {
            for (idx, expectedType) in expectedTypes.enumerated() where idx < args.count {
                let actualType = inferType(of: args[idx], in: scope)
                if expectedType != .any && actualType != expectedType && actualType != .any {
                    recordError("\(name) expects \(expectedType) for argument \(idx+1), got \(actualType)", line)
                }
            }
        }
    }

    // -----------------------------
    // Handlers for Constructs
    // -----------------------------
    private func checkSetq(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool, inFunc: Bool) {
        guard elements.count == 3 else {
            recordError("setq requires exactly 2 arguments, got \(elements.count - 1)", line)
            return
        }
        guard case .atom(let name) = elements[1] else {
            recordError("first argument of setq must be an atom", line)
            return
        }

        let value = elements[2]
        analyzeNode(value, in: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
        let valueType = inferType(of: value, in: scope)
        scope.defineVariable(name, type: valueType)
    }
    
    private func checkQuote(_ elements: [Element], line: Int) {
        if elements.count != 2 {
            recordError("quote requires exactly 1 argument, got \(elements.count - 1)", line)
        }
    }

    private func checkFunc(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count == 4 else {
            recordError("func requires exactly 3 arguments, got \(elements.count - 1)", line)
            return
        }
        guard case .atom(let fname) = elements[1] else {
            recordError("first argument of func must be an atom", line)
            return
        }
        guard case .list(let paramsList) = elements[2] else {
            recordError("second argument of func must be a list of parameters", line)
            return
        }
        
        let params: [String] = paramsList.compactMap {
            if case .atom(let p) = $0 { return p }
            recordError("parameter in func must be an atom", line)
            return nil
        }
        
        scope.defineFunction(fname, params: params, body: elements[3])

        let fnScope = SymbolTable(parent: scope)
        for p in params {
            fnScope.defineVariable(p, type: .any)
        }
        analyzeNode(elements[3], in: fnScope, line: line, inProg: false, inWhile: false, inFunc: true)
    }

    private func checkLambda(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count == 3 else {
            recordError("lambda requires exactly 2 arguments, got \(elements.count - 1)", line)
            return
        }
        guard case .list(let params) = elements[1] else {
            recordError("first argument of lambda must be a list of parameters", line)
            return
        }
        
        let local = SymbolTable(parent: scope)
        for p in params {
            if case .atom(let name) = p {
                local.defineVariable(name, type: .any)
            } else {
                recordError("lambda parameter must be an atom", line)
            }
        }
        analyzeNode(elements[2], in: local, line: line, inProg: false, inWhile: false, inFunc: false)
    }

    private func checkProg(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count >= 3 else {
            recordError("prog requires at least 2 arguments", line)
            return
        }
        guard case .list(let locals) = elements[1] else {
            recordError("first argument of prog must be a list of local variables", line)
            return
        }

        let localScope = SymbolTable(parent: scope)
        for v in locals {
            if case .atom(let name) = v {
                localScope.defineVariable(name, type: .any)
            } else {
                recordError("prog local variable must be an atom", line)
            }
        }

        for expr in elements.dropFirst(2) {
            analyzeNode(expr, in: localScope, line: line, inProg: true, inWhile: false, inFunc: false)
        }
    }

    private func checkCond(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool, inFunc: Bool) {
        if elements.count < 3 || elements.count > 4 {
            recordError("cond requires 2 or 3 arguments, got \(elements.count - 1)", line)
            return
        }
        
        analyzeNode(elements[1], in: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
        let condType = inferType(of: elements[1], in: scope)
        if condType != .bool && condType != .any {
            recordError("cond expects a boolean condition, got \(condType)", line)
        }
        
        analyzeNode(elements[2], in: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
        
        if elements.count == 4 {
            analyzeNode(elements[3], in: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
        }
    }

    private func checkWhile(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inFunc: Bool) {
        guard elements.count >= 3 else {
            recordError("while requires at least 2 arguments, got \(elements.count - 1)", line)
            return
        }
        
        analyzeNode(elements[1], in: scope, line: line, inProg: inProg, inWhile: false, inFunc: inFunc)
        let condType = inferType(of: elements[1], in: scope)
        if condType != .bool && condType != .any {
            recordError("while expects a boolean condition, got \(condType)", line)
        }

        for bodyExpr in elements.dropFirst(2) {
            analyzeNode(bodyExpr, in: scope, line: line, inProg: inProg, inWhile: true, inFunc: inFunc)
        }
    }

    private func checkReturn(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inFunc: Bool) {
        if !inProg && !inFunc {
            recordError("return used outside of prog or function", line)
            return
        }
        
        if elements.count > 2 {
            recordError("return expects 0 or 1 arguments, got \(elements.count - 1)", line)
        }
        
        if elements.count == 2 {
            analyzeNode(elements[1], in: scope, line: line, inProg: false, inWhile: false, inFunc: inFunc)
        }
    }

    private func checkFunctionCall(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool, inFunc: Bool) {
        guard case .atom(let name) = elements[0] else {
            for elem in elements {
                analyzeNode(elem, in: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
            }
            return
        }

        if !Self.isBuiltinSymbol(name)
            && scope.lookupFunction(name) == nil
            && !scope.isVariableDefined(name) {
            recordError("Call to undefined function '\(name)'", line)
        }

        let args = Array(elements.dropFirst())
        for arg in args {
            analyzeNode(arg, in: scope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
        }

        if Self.isBuiltinSymbol(name) {
            checkBuiltinCall(name, args: args, in: scope, line: line)
            return
        }

        if let (params, _) = scope.lookupFunction(name) {
            if params.count != args.count {
                recordError("\(name) expects \(params.count) argument(s), got \(args.count)", line)
            }
        }
    }

    private func handleAnonymousLambdaCall(innerLambda: [Element], callArgs: [Element], parentScope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool, inFunc: Bool) {
        guard innerLambda.count == 3 else {
            recordError("lambda must have exactly 2 arguments (parameters and body)", line)
            return
        }
        guard case .list(let paramList) = innerLambda[1] else {
            recordError("lambda parameters must be a list", line)
            return
        }
        
        let params: [String] = paramList.compactMap {
            if case .atom(let p) = $0 { return p } else {
                recordError("lambda parameter must be an atom", line)
                return nil
            }
        }
        
        if params.count != callArgs.count {
            recordError("anonymous lambda expects \(params.count) argument(s), got \(callArgs.count)", line)
        }

        for arg in callArgs {
            analyzeNode(arg, in: parentScope, line: line, inProg: inProg, inWhile: inWhile, inFunc: inFunc)
        }

        let lambdaScope = SymbolTable(parent: parentScope)
        for p in params {
            lambdaScope.defineVariable(p, type: .any)
        }
        analyzeNode(innerLambda[2], in: lambdaScope, line: line, inProg: false, inWhile: false, inFunc: false)
    }

    // MARK: - Helpers
    private func recordError(_ message: String, _ line: Int) {
        errors.append(SemanticError(message: message, line: line))
    }

    private static func isBuiltinSymbol(_ name: String) -> Bool {
        return builtinSymbols.contains(name)
    }

    private static let builtinSymbols: Set<String> = [
        "quote", "setq", "func", "lambda", "prog", "cond",
        "while", "return", "break",
        "plus", "minus", "times", "divide",
        "head", "tail", "cons",
        "equal", "nonequal", "less", "lesseq", "greater", "greatereq",
        "isint", "isreal", "isbool", "isnull", "isatom", "islist",
        "and", "or", "xor", "not",
        "eval"
    ]
}
