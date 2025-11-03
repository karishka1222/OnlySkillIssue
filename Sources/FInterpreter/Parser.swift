import Foundation

// MARK: - Node wrapper (Element + line number)
public struct Node: CustomStringConvertible {
    public let element: Element
    public let line: Int

    public var description: String {
        "\(element) [line \(line)]"
    }
}

// AST: Element
public indirect enum Element: CustomStringConvertible {
    case atom(String)
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    case null
    case list([Element])
    
    public var description: String {
        switch self {
        case .atom(let s): return s
        case .integer(let i): return String(i)
        case .real(let r): return String(r)
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "null"
        case .list(let elems):
            let inner = elems.map { $0.description }.joined(separator: " ")
            return "(\(inner))"
        }
    }
    
    public func prettyDescription(_ indent: String = "", isLast: Bool = true) -> String {
        let prefix = indent + (isLast ? "└── " : "├── ")

        switch self {
        case .atom(let s):
            return "\(prefix)AtomNode(\"\(s)\")"
        case .integer(let i):
            return "\(prefix)LiteralNode(\(i))"
        case .real(let r):
            return "\(prefix)LiteralNode(\(r))"
        case .boolean(let b):
            return "\(prefix)LiteralNode(\(b))"
        case .null:
            return "\(prefix)LiteralNode(null)"
        case .list(let elems):
            var result = "\(prefix)ListNode"
            for (index, child) in elems.enumerated() {
                let isLastChild = index == elems.count - 1
                let childIndent = indent + (isLast ? "    " : "│   ")
                result += "\n" + child.prettyDescription(childIndent, isLast: isLastChild)
            }
            return result
        }
    }
}

public enum ParserError: Error, CustomStringConvertible {
    case unexpectedEOF
    case unexpectedToken(String)
    case missingRParen
    case generic(String)
    
    public var description: String {
        switch self {
        case .unexpectedEOF: return "ParserError: unexpected end of input"
        case .missingRParen: return "ParserError: missing closing parenthesis"
        case .unexpectedToken(let t): return "ParserError: unexpected token '\(t)'"
        case .generic(let s): return "ParserError: \(s)"
        }
    }
}

public struct ParserErrorRecord: CustomStringConvertible {
    public let line: Int
    public let message: String

    public var description: String {
        "Line \(line): \(message)"
    }
}

public final class Parser {
    private let tokens: [Token]
    private var pos: Int = 0
    private let lenient: Bool

    /// Collected errors during parsing (non-fatal). Public for inspection after parsing.
    public private(set) var errors: [ParserErrorRecord] = []

    /// - parameters:
    ///   - tokens: список токенов от Lexer
    ///   - lenient: если true — unknown-токены не будут падать, а будут превращены в Atom (удобно для batch-тестов)
    public init(tokens: [Token], lenient: Bool = false) {
        self.tokens = tokens
        self.lenient = lenient
    }

    public func parseProgram() -> [Node] {
        var nodes: [Node] = []
        // Сбрасываем предыдущие ошибки и позицию (если кто-то переиспользует парсер)
        errors = []
        pos = 0

        while let t = peek() {
            if case .newline = t {
                advance(); continue
            }
            if case .unknown(let s) = t, lenient {
                _ = advance()
                let line = currentLineNumber()
                nodes.append(Node(element: .atom(s), line: line))
                continue
            }

            do {
                let node = try parseElement()
                nodes.append(node)
            } catch let pErr as ParserError {
                let line = currentLineNumber()
                recordError(line: line, message: pErr.description)
                // Попробуем восстановиться и продолжить разбор:
                recover()
                continue
            } catch {
                let line = currentLineNumber()
                recordError(line: line, message: "Unknown error: \(error)")
                recover()
                continue
            }
        }
        return nodes
    }

    public func parseElement() throws -> Node {
        let line = currentLineNumber() // запоминаем строку, где встретили элемент
        guard let token = peek() else { throw ParserError.unexpectedEOF }

        switch token {
        case .integer(let v):
            advance(); return Node(element: .integer(v), line: line)
        case .real(let r):
            advance(); return Node(element: .real(r), line: line)
        case .boolean(let b):
            advance(); return Node(element: .boolean(b), line: line)
        case .null:
            advance(); return Node(element: .null, line: line)
        case .identifier(let name):
            advance(); return Node(element: .atom(name), line: line)
        case .keyword(let name):
            advance(); return Node(element: .atom(name), line: line)
        case .quote:
            // 'x  -> (quote x)
            advance()
            guard peek() != nil else { throw ParserError.unexpectedEOF }
            let quoted = try parseElement()
            return Node(element: .list([.atom("quote"), quoted.element]), line: line)
        case .lparen:
            advance()
            var elems: [Element] = []
            // parse elements until matching rparen
            while true {
                guard let t = peek() else {
                    // EOF inside list -> report missing rparen
                    throw ParserError.missingRParen
                }
                if case .rparen = t {
                    advance(); break
                }
                if case .newline = t {
                    advance(); continue
                }
                if case .unknown(let s) = t, lenient {
                    _ = advance()
                    elems.append(.atom(s))
                    continue
                }
                let child = try parseElement()
                elems.append(child.element)
            }
            return Node(element: .list(elems), line: line)
        case .rparen:
            throw ParserError.unexpectedToken(")")
        case .newline:
            advance()
            return try parseElement()
        case .unknown(let s):
            if lenient {
                _ = advance()
                return Node(element: .atom(s), line: line)
            } else {
                throw ParserError.unexpectedToken(s)
            }
        }
    }

    // MARK: - helpers

    private func peek() -> Token? {
        pos < tokens.count ? tokens[pos] : nil
    }
    @discardableResult
    private func advance() -> Token? {
        guard pos < tokens.count else { return nil }
        let t = tokens[pos]; pos += 1; return t
    }

    private func currentLineNumber() -> Int {
        let newlines = tokens.prefix(pos).filter {
            if case .newline = $0 { return true }
            return false
        }.count
        return newlines + 1
    }

    private func recordError(line: Int, message: String) {
        let rec = ParserErrorRecord(line: line, message: message)
        errors.append(rec)
    }

    /// Попытка безопасно восстановиться после ошибки:
    /// пробегаем токены, пока не встретим:
    /// - newline (тогда считаем, что следующая строка — безопасное место)
    /// - rparen (закрывающая скобка — возможно конец текущего выражения)
    /// В любом случае, чтобы не зациклиться, если ничего не найдено — сдвигаемся на один токен.
    private func recover() {
        // Если уже в конце, ничего делать не нужно
        if peek() == nil { return }

        // Попробуем найти ближайшую "точку синхронизации"
        var progressed = false
        while let t = peek() {
            switch t {
            case .newline:
                // пропускаем саму newline и считаем, что позиция после неё безопасна
                _ = advance()
                progressed = true
                return
            case .rparen:
                // пропускаем rparen чтобы выйти из неправильной вложенности
                _ = advance()
                progressed = true
                return
            case .lparen:
                // если встретили новую lparen — остановимся, т.к. внутри неё может быть корректное выражение
                return
            default:
                // просто пропускаем токен и продолжаем поиск
                _ = advance()
                progressed = true
                continue
            }
        }

        // Если мы ничего не продвинули (маловероятно), сдвинемся на один токен, чтобы избежать бесконечного цикла
        if !progressed {
            _ = advance()
        }
    }
}
