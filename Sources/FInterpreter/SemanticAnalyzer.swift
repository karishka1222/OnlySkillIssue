import Foundation

// MARK: - Semantic Error
public struct SemanticError: Error, CustomStringConvertible {
    public let message: String
    public let line: Int
    public var description: String {
        "⚠️ Semantic error at line \(line): \(message)"
    }
}

public enum TypeKind: Equatable, CustomStringConvertible {
    case number
    case bool
    case any

    public var description: String {
        switch self {
        case .number: return "number"
        case .bool: return "bool"
        case .any: return "any"
        }
    }
}

// -----------------------------
// SymbolTable
// -----------------------------
public final class SymbolTable {
    private var variables: [String: TypeKind] = [:]
    private var functions: [String: ([String], Element)] = [:]
    private weak var parent: SymbolTable? // weak чтобы избежать удерживающих циклов

    public init(parent: SymbolTable? = nil) {
        self.parent = parent
    }

    public func defineVariable(_ name: String, type: TypeKind = .any) {
        variables[name] = type
    }

    public func isVariableDefined(_ name: String) -> Bool {
        return lookupVariableType(name) != nil
    }

    // Итеративный lookup с защитой от циклов
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

    // Итеративный lookup функций с защитой от циклов
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

// -----------------------------
// Semantic Analyzer
// -----------------------------
public final class SemanticAnalyzer {
    private let ast: [Node]
    private var errors: [SemanticError] = []
    private let globalScope = SymbolTable()

    public init(ast: [Node]) {
        self.ast = ast
    }

    // Внешняя точка
    public func analyze() -> [SemanticError] {
        for node in ast {
            analyzeNode(node.element, in: globalScope, line: node.line, inProg: false, inWhile: false)
        }
        return errors
    }

    // MARK: - analyzeNode
    private func analyzeNode(_ element: Element, in scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool) {
        switch element {
        case .atom(let name):
            if !Self.isBuiltinSymbol(name) && !scope.isVariableDefined(name) && scope.lookupFunction(name) == nil {
                recordError("Undeclared identifier '\(name)'", line)
            }

        case .list(let elements):
            // защита от анализа содержимого quote
            if let first = elements.first, case .atom(let head) = first, head == "quote" {
                return
            }

            guard let first = elements.first else { return }

            // ((lambda (...) body) args...) — анонимный вызов
            if case .list(let inner) = first,
               let innerFirst = inner.first,
               case .atom(let innerHead) = innerFirst,
               innerHead == "lambda" {
                handleAnonymousLambdaCall(innerLambda: inner, callArgs: Array(elements.dropFirst()), parentScope: scope, line: line, inProg: inProg, inWhile: inWhile)
                return
            }

            if case .atom(let head) = first {
                switch head {
                case "setq":
                    checkSetq(elements, scope: scope, line: line, inProg: inProg, inWhile: inWhile)
                case "func":
                    checkFunc(elements, scope: scope, line: line)
                case "lambda":
                    checkLambda(elements, scope: scope, line: line)
                case "prog":
                    checkProg(elements, scope: scope, line: line)
                case "cond":
                    checkCond(elements, scope: scope, line: line, inProg: inProg, inWhile: inWhile)
                case "while":
                    checkWhile(elements, scope: scope, line: line)
                case "return":
                    if !inProg {
                        recordError("return used outside of prog", line)
                    } else {
                        for expr in elements.dropFirst() {
                            analyzeNode(expr, in: scope, line: line, inProg: inProg, inWhile: inWhile)
                        }
                    }
                case "break":
                    if !inWhile {
                        recordError("break used outside of while", line)
                    }
                default:
                    checkFunctionCall(elements, scope: scope, line: line, inProg: inProg, inWhile: inWhile)
                }
            }
        default: break
        }
    }

    // MARK: - Builtin specs (арность + типы)
    private struct BuiltinSpec {
        let arity: Int?
        let expectedArgTypes: [TypeKind]?
        let returnType: TypeKind?
    }

    private let builtinSpecs: [String: BuiltinSpec] = [
        "plus":   BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),
        "minus":  BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),
        "times":  BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),
        "divide": BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .number),

        "less": BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .bool),
        "greater": BuiltinSpec(arity: 2, expectedArgTypes: [.number, .number], returnType: .bool),
        "equal": BuiltinSpec(arity: 2, expectedArgTypes: nil, returnType: .bool),
        "nonequal": BuiltinSpec(arity: 2, expectedArgTypes: nil, returnType: .bool),

        "head": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .any),
        "tail": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .any),
        "cons": BuiltinSpec(arity: 2, expectedArgTypes: nil, returnType: .any),

        "and": BuiltinSpec(arity: 2, expectedArgTypes: [.bool, .bool], returnType: .bool),
        "or": BuiltinSpec(arity: 2, expectedArgTypes: [.bool, .bool], returnType: .bool),
        "xor": BuiltinSpec(arity: 2, expectedArgTypes: [.bool, .bool], returnType: .bool),
        "not": BuiltinSpec(arity: 1, expectedArgTypes: [.bool], returnType: .bool),

        "isint": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "isreal": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "isatom": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "islist": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),
        "isnull": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .bool),

        "eval": BuiltinSpec(arity: 1, expectedArgTypes: nil, returnType: .any)
    ]

    // MARK: - Type inference
    private func inferType(of element: Element, in scope: SymbolTable? = nil, depth: Int = 0) -> TypeKind {
        if depth > 4 { return .any }

        switch element {
        case .integer(_), .real(_):
            return .number
        case .boolean(_):
            return .bool
        case .atom(let name):
            if let s = scope, let t = s.lookupVariableType(name) { return t }
            return .any
        case .list(let elems):
            guard let first = elems.first else { return .any }
            if case .atom(let head) = first {
                if let spec = builtinSpecs[head] {
                    return spec.returnType ?? .any
                }
                if let _ = scope?.lookupFunction(head) {
                    return .any
                }
            }
            return .any
        default:
            return .any
        }
    }

    // MARK: - Builtin call checks
    private func checkBuiltinCall(_ name: String, args: [Element], in scope: SymbolTable, line: Int) {
        guard let spec = builtinSpecs[name] else { return }

        // 1) арность
        if let ar = spec.arity, args.count != ar {
            recordError("\(name) expects \(ar) argument(s), got \(args.count)", line)
        }

        // 2) типы аргументов (если заданы)
        if let expected = spec.expectedArgTypes {
            for (idx, expectedType) in expected.enumerated() where idx < args.count {
                let actual = inferType(of: args[idx], in: scope)
                // Если тип неизвестен (.any), не считаем это ошибкой — параметры функций/лямбд допустимы
                if actual == .any { continue }
                if expectedType != .any && actual != expectedType {
                    recordError("\(name) expects \(expectedType) for arg \(idx+1), got \(actual)", line)
                }
            }
        }
    }

    // -----------------------------
    // Handlers for constructs
    // -----------------------------
    private func checkSetq(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool) {
        guard elements.count == 3 else {
            recordError("setq requires 2 arguments", line)
            return
        }
        guard case .atom(let name) = elements[1] else {
            recordError("first argument of setq must be an atom", line)
            return
        }

        let value = elements[2]
        analyzeNode(value, in: scope, line: line, inProg: inProg, inWhile: inWhile)
        let valueType = inferType(of: value, in: scope)
        scope.defineVariable(name, type: valueType)
    }

    private func checkFunc(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count >= 4 else {
            recordError("func requires 3 arguments", line)
            return
        }
        guard case .atom(let fname) = elements[1] else {
            recordError("first argument of func must be an atom", line)
            return
        }
        guard case .list(let paramsList) = elements[2] else {
            recordError("second argument of func must be a list", line)
            return
        }
        let params: [String] = paramsList.compactMap {
            if case .atom(let p) = $0 { return p }
            recordError("parameter in func must be an atom", line)
            return nil
        }
        scope.defineFunction(fname, params: params, body: elements[3])

        // Однократный анализ тела в fresh scope
        let fnScope = SymbolTable(parent: scope)
        for p in params { fnScope.defineVariable(p, type: .any) }
        analyzeNode(elements[3], in: fnScope, line: line, inProg: false, inWhile: false)
    }

    private func checkLambda(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count == 3 else {
            recordError("lambda requires 2 arguments", line)
            return
        }
        guard case .list(let params) = elements[1] else {
            recordError("first argument of lambda must be a list", line)
            return
        }
        let local = SymbolTable(parent: scope)
        for p in params {
            if case .atom(let name) = p {
                local.defineVariable(name)
            } else {
                recordError("lambda parameter must be an atom", line)
            }
        }
        analyzeNode(elements[2], in: local, line: line, inProg: false, inWhile: false)
    }

    private func checkProg(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count >= 3 else {
            recordError("prog requires at least 2 arguments", line)
            return
        }
        guard case .list(let locals) = elements[1] else {
            recordError("first argument of prog must be list of local vars", line)
            return
        }

        let names: [String] = locals.compactMap {
            if case .atom(let n) = $0 { return n }
            return nil
        }
        if Set(names).count != names.count {
            recordError("prog local variable list contains duplicates", line)
        }

        let localScope = SymbolTable(parent: scope)
        for v in locals {
            if case .atom(let name) = v {
                localScope.defineVariable(name)
            } else {
                recordError("prog local variable must be an atom", line)
            }
        }

        for expr in elements.dropFirst(2) {
            analyzeNode(expr, in: localScope, line: line, inProg: true, inWhile: false)
        }
    }

    private func checkCond(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool) {
        if elements.count < 3 || elements.count > 4 {
            recordError("cond requires 2 or 3 arguments", line)
            return
        }
        analyzeNode(elements[1], in: scope, line: line, inProg: inProg, inWhile: inWhile)
        let condType = inferType(of: elements[1], in: scope)
        if condType != .bool {
            recordError("cond expects a bool condition, got \(condType)", line)
        }
        analyzeNode(elements[2], in: scope, line: line, inProg: inProg, inWhile: inWhile)
        if elements.count == 4 {
            analyzeNode(elements[3], in: scope, line: line, inProg: inProg, inWhile: inWhile)
        }
    }

    private func checkWhile(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count >= 3 else {
            recordError("while requires 2 arguments", line)
            return
        }
        analyzeNode(elements[1], in: scope, line: line, inProg: false, inWhile: false)
        let condType = inferType(of: elements[1], in: scope)
        if condType != .bool {
            recordError("while expects a bool condition, got \(condType)", line)
        }

        for bodyExpr in elements.dropFirst(2) {
            analyzeNode(bodyExpr, in: scope, line: line, inProg: false, inWhile: true)
        }
    }

    // Вызов функции/лямбды
    private func checkFunctionCall(_ elements: [Element], scope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool) {
        guard case .atom(let name) = elements[0] else { return }

        // 1) наличие определения
        if !Self.isBuiltinSymbol(name)
            && scope.lookupFunction(name) == nil
            && !scope.isVariableDefined(name) {
            recordError("Call to undefined function '\(name)'", line)
        }

        // 2) анализ аргументов
        let args = Array(elements.dropFirst())
        for arg in args {
            analyzeNode(arg, in: scope, line: line, inProg: inProg, inWhile: inWhile)
        }

        // 3) builtin — арность/типы
        if Self.isBuiltinSymbol(name) {
            checkBuiltinCall(name, args: args, in: scope, line: line)
            return
        }

        // 4) пользовательская функция — проверяем только арность
        if let (params, _) = scope.lookupFunction(name) {
            if params.count != args.count {
                recordError("\(name) expects \(params.count) argument(s), got \(args.count)", line)
            }
        }
    }

    // ((lambda (...) body) arg1 arg2)
    private func handleAnonymousLambdaCall(innerLambda: [Element], callArgs: [Element], parentScope: SymbolTable, line: Int, inProg: Bool, inWhile: Bool) {
        guard innerLambda.count == 3 else {
            recordError("lambda must have parameter list and body", line)
            return
        }
        guard case .list(let paramList) = innerLambda[1] else {
            recordError("lambda params must be a list", line)
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

        // анализируем только аргументы вызова (без анализа тела снова)
        for a in callArgs {
            analyzeNode(a, in: parentScope, line: line, inProg: inProg, inWhile: inWhile)
        }
    }

    // MARK: - Helpers
    private func recordError(_ message: String, _ line: Int) {
        errors.append(SemanticError(message: message, line: line))
    }

    private static func isBuiltinSymbol(_ name: String) -> Bool {
        switch name {
        case "quote", "setq", "func", "lambda", "prog", "cond",
             "while", "return", "break",
             "plus", "minus", "times", "divide",
             "head", "tail", "cons",
             "equal", "nonequal", "less",
             "lesseq", "greater", "greatereq",
             "isint", "isreal", "isbool", "isnull", "isatom", "islist",
             "and", "or", "xor", "not", "eval":
            return true
        default:
            return false
        }
    }
}
