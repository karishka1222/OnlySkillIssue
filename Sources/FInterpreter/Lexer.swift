public enum Token {
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    case null
    case identifier(String)
    case keyword(String)
    case quote
    case lparen
    case rparen
    case newline
    case unknown(String)
}

extension Token: CustomStringConvertible {
    public var description: String {
        switch self {
        case .integer(let value): return "integer(\(value))"
        case .real(let value): return "real(\(value))"
        case .boolean(let value): return "boolean(\(value))"
        case .null: return "null"
        case .identifier(let name): return "identifier(\(name))"
        case .keyword(let name): return "keyword(\(name))"
        case .quote: return "quote"
        case .lparen: return "lparen"
        case .rparen: return "rparen"
        case .newline: return "newline"
        case .unknown(let value): return "unknown(\(value))"
        }
    }
}

public class Lexer {
    private let input: String
    private var position: String.Index
    
    private let keywords: Set<String> = [
        "quote", "setq", "func", "lambda", "prog", "cond",
        "while", "return", "break",
        "plus", "minus", "times", "divide",
        "head", "tail", "cons",
        "equal", "nonequal", "less",
        "lesseq", "greater", "greatereq",
        "isint", "isreal", "isbool", "isnull", "isatom", "islist",
        "and", "or", "xor", "not", "eval"
    ]
    
    public init(input: String) {
        self.input = input
        self.position = input.startIndex
    }
    
    public func tokenize() -> [Token] {
        var tokens: [Token] = []
        
        while let char = peek() {
            if char == "\n" {
                tokens.append(.newline)
                advance()
                continue
            }
            
            if char.isWhitespace {
                advance()
                continue
            }
            
            switch char {
            case "(":
                tokens.append(.lparen)
                advance()
            case ")":
                tokens.append(.rparen)
                advance()
            case "'":
                tokens.append(.quote)
                advance()
            default:
                let atom = readAtom()
                
                if atom == "true" {
                    tokens.append(.boolean(true))
                } else if atom == "false" {
                    tokens.append(.boolean(false))
                } else if atom == "null" {
                    tokens.append(.null)
                } else if keywords.contains(atom) {
                    tokens.append(.keyword(atom))
                } else if let intVal = Int(atom) {
                    tokens.append(.integer(intVal))
                } else if let realVal = Double(atom) {
                    tokens.append(.real(realVal))
                } else if atom.allSatisfy({ $0.isLetter }) {
                    tokens.append(.identifier(atom))
                } else {
                    tokens.append(.unknown(atom))
                }
            }
        }
        
        return tokens
    }
    
    private func readAtom() -> String {
        var result = ""
        while let c = peek(),
              !c.isWhitespace,
              c != "(",
              c != ")",
              c != "'" {
            result.append(c)
            advance()
        }
        return result
    }
    
    private func peek() -> Character? {
        position < input.endIndex ? input[position] : nil
    }
    
    private func advance() {
        position = input.index(after: position)
    }
}
