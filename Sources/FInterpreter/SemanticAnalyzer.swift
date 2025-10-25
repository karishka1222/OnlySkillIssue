import Foundation

// MARK: - Semantic Error
public struct SemanticError: Error, CustomStringConvertible {
    public let message: String
    public let line: Int
    public var description: String {
        "⚠️ Semantic error at line \(line): \(message)"
    }
}

// MARK: - Symbol Table
public final class SymbolTable {
    private var variables: Set<String> = []
    private var functions: [String: ([String], Element)] = [:]
    private var parent: SymbolTable?

    public init(parent: SymbolTable? = nil) {
        self.parent = parent
    }

    public func defineVariable(_ name: String) {
        variables.insert(name)
    }

    public func isVariableDefined(_ name: String) -> Bool {
        if variables.contains(name) { return true }
        return parent?.isVariableDefined(name) ?? false
    }

    public func defineFunction(_ name: String, params: [String], body: Element) {
        functions[name] = (params, body)
    }

    public func lookupFunction(_ name: String) -> ([String], Element)? {
        if let f = functions[name] { return f }
        return parent?.lookupFunction(name)
    }
}

// MARK: - Semantic Analyzer
public final class SemanticAnalyzer {
    private let ast: [Node]
    private var errors: [SemanticError] = []
    private let globalScope = SymbolTable()
    
    public init(ast: [Node]) {
        self.ast = ast
    }
    
    public func analyze() -> [SemanticError] {
        for node in ast {
            analyzeNode(node.element, in: globalScope, line: node.line)
        }
        return errors
    }

    private func analyzeNode(_ element: Element, in scope: SymbolTable, line: Int) {
        switch element {
        case .atom(let name):
            if !isBuiltinSymbol(name) && !scope.isVariableDefined(name) && scope.lookupFunction(name) == nil {
                recordError("Undeclared identifier '\(name)'", line)
            }

        case .list(let elements):
            guard let first = elements.first else { return }
            if case .atom(let head) = first {
                switch head {
                case "setq":
                    checkSetq(elements, scope: scope, line: line)
                case "func":
                    checkFunc(elements, scope: scope, line: line)
                case "lambda":
                    checkLambda(elements, scope: scope, line: line)
                case "prog":
                    checkProg(elements, scope: scope, line: line)
                case "cond":
                    checkCond(elements, scope: scope, line: line)
                case "while":
                    checkWhile(elements, scope: scope, line: line)
                case "return", "break":
                    break // допустим, не проверяем контекст пока
                default:
                    checkFunctionCall(elements, scope: scope, line: line)
                }
            }

        default: break
        }
    }

    private func checkSetq(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count == 3 else {
            recordError("setq requires 2 arguments", line)
            return
        }
        guard case .atom(let name) = elements[1] else {
            recordError("first argument of setq must be an atom", line)
            return
        }
        analyzeNode(elements[2], in: scope, line: line)
        scope.defineVariable(name)
    }

    private func checkFunc(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count >= 4 else {
            recordError("func requires 3 arguments", line)
            return
        }
        guard case .atom(let name) = elements[1] else {
            recordError("first argument of func must be an atom (function name)", line)
            return
        }
        guard case .list(let paramsList) = elements[2] else {
            recordError("second argument of func must be a list of parameters", line)
            return
        }
        let params: [String] = paramsList.compactMap {
            if case .atom(let p) = $0 { return p }
            else {
                recordError("parameter in func must be an atom", line)
                return nil
            }
        }
        scope.defineFunction(name, params: params, body: elements[3])
    }

    private func checkLambda(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count == 3 else {
            recordError("lambda requires 2 arguments", line)
            return
        }
        guard case .list(let params) = elements[1] else {
            recordError("first argument of lambda must be a list of parameters", line)
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
        analyzeNode(elements[2], in: local, line: line)
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
        let local = SymbolTable(parent: scope)
        for v in locals {
            if case .atom(let name) = v {
                local.defineVariable(name)
            } else {
                recordError("prog local variable must be an atom", line)
            }
        }
        for expr in elements.dropFirst(2) {
            analyzeNode(expr, in: local, line: line)
        }
    }

    private func checkCond(_ elements: [Element], scope: SymbolTable, line: Int) {
        if elements.count < 3 || elements.count > 4 {
            recordError("cond requires 2 or 3 arguments", line)
            return
        }
        analyzeNode(elements[1], in: scope, line: line)
        analyzeNode(elements[2], in: scope, line: line)
        if elements.count == 4 {
            analyzeNode(elements[3], in: scope, line: line)
        }
    }

    private func checkWhile(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard elements.count == 3 else {
            recordError("while requires 2 arguments", line)
            return
        }
        analyzeNode(elements[1], in: scope, line: line)
        analyzeNode(elements[2], in: scope, line: line)
    }

    private func checkFunctionCall(_ elements: [Element], scope: SymbolTable, line: Int) {
        guard case .atom(let name) = elements[0] else { return }
        if !isBuiltinSymbol(name) && scope.lookupFunction(name) == nil {
            recordError("Call to undefined function '\(name)'", line)
        }
        for arg in elements.dropFirst() {
            analyzeNode(arg, in: scope, line: line)
        }
    }

    private func recordError(_ message: String, _ line: Int) {
        errors.append(SemanticError(message: message, line: line))
    }

    private func isBuiltinSymbol(_ name: String) -> Bool {
        return [
            "quote", "setq", "func", "lambda", "prog", "cond",
            "while", "return", "break",
            "plus", "minus", "times", "divide",
            "head", "tail", "cons",
            "equal", "nonequal", "less",
            "lesseq", "greater", "greatereq",
            "isint", "isreal", "isbool", "isnull", "isatom", "islist",
            "and", "or", "xor", "not", "eval"
        ].contains(name)
    }
}
