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

public final class Parser {
    private let tokens: [Token]
    private var pos: Int = 0
    private let lenient: Bool
    
    /// - parameters:
    ///   - tokens: список токенов от Lexer
    ///   - lenient: если true — unknown-токены не будут падать, а будут превращены в Atom (удобно для batch-тестов)
    public init(tokens: [Token], lenient: Bool = false) {
        self.tokens = tokens
        self.lenient = lenient
    }
    
    public func parseProgram() throws -> [Node] {
        var nodes: [Node] = []
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
            } catch let error as ParserError {
                let line = currentLineNumber()
                print("⚠️ Syntax error at line \(line): \(error)")
                _ = advance()
                continue
            } catch {
                let line = currentLineNumber()
                print("⚠️ Unknown error at line \(line): \(error)")
                _ = advance()
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
            advance()
            guard peek() != nil else { throw ParserError.unexpectedEOF }
            let quoted = try parseElement()
            return Node(element: .list([.atom("quote"), quoted.element]), line: line)
        case .lparen:
            advance()
            var elems: [Element] = []
            while true {
                guard let t = peek() else { throw ParserError.missingRParen }
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
    
    // MARK: helpers
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
}
