import Foundation

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
    
    public func parseProgram() throws -> [Element] {
        var elements: [Element] = []
        while let t = peek() {
            // пропускаем пустые строки
            if case .newline = t {
                advance(); continue
            }
            // В lenient режиме можно пропускать unknown (или трактовать их как atom)
            if case .unknown(let s) = t, lenient {
                // конвертим unknown в атом и продолжаем (можно также просто advance() чтобы игнорировать)
                _ = advance()
                elements.append(.atom(s))
                continue
            }
            elements.append(try parseElement())
        }
        return elements
    }
    
    public func parseElement() throws -> Element {
        guard let token = peek() else { throw ParserError.unexpectedEOF }
        
        switch token {
        case .integer(let v):
            advance(); return .integer(v)
        case .real(let r):
            advance(); return .real(r)
        case .boolean(let b):
            advance(); return .boolean(b)
        case .null:
            advance(); return .null
        case .identifier(let name):
            advance(); return .atom(name)
        case .keyword(let name):
            // любая ключевое слово в позиции элемента просто атом (например plus, isint, cond и т.д.)
            advance(); return .atom(name)
        case .quote:
            // короткая форма: 'Element  ->  (quote Element)
            advance()
            // за апострофом обязательно должен идти Element
            guard peek() != nil else { throw ParserError.unexpectedEOF }
            let quoted = try parseElement()
            return .list([.atom("quote"), quoted])
        case .lparen:
            advance() // consume '('
            var elems: [Element] = []
            while true {
                guard let t = peek() else { throw ParserError.missingRParen }
                if case .rparen = t {
                    advance(); break
                }
                if case .newline = t {
                    advance(); continue
                }
                // unknown inside list
                if case .unknown(let s) = t, lenient {
                    // либо превратить в atom, либо пропустить; я выбираю atom для видимости
                    _ = advance()
                    elems.append(.atom(s))
                    continue
                }
                let child = try parseElement()
                elems.append(child)
            }
            return .list(elems)
        case .rparen:
            // лишняя закрывающая скобка
            throw ParserError.unexpectedToken(")")
        case .newline:
            advance()
            return try parseElement()
        case .unknown(let s):
            // В строгом режиме — ошибка
            if lenient {
                _ = advance()
                return .atom(s)
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
}
