import Foundation

public enum Token {
    case number(Double)
    case boolean(Bool)
    case null
    case identifier(String)
    case keyword(String)
    case quote
    case lparen
    case rparen
}

public class Lexer {
    private let input: String
    private var position: String.Index
    
    private let keywords: Set<String> = [
        "setq", "func", "lambda", "prog", "return",
        "cond", "while", "break", "eval",
        "plus", "minus", "times", "divide",
        "less", "greater", "equal",
        "and", "or", "xor", "not",
        "isint", "isreal", "isatom", "islist", "isnull",
        "true", "false", "null"
    ]
    
    public init(input: String) {
        self.input = input
        self.position = input.startIndex
    }
    
    public func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        
        while let char = peek() {
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
            case "+":
                tokens.append(.keyword("plus"))
                advance()
            case "-":
                if let next = peekNext(), next.isNumber {
                    let numStr = readWhile { $0.isNumber || $0 == "." || $0 == "-" }
                    if let num = Double(numStr) {
                        tokens.append(.number(num))
                    } else {
                        throw LexerError.invalidNumber(numStr)
                    }
                } else {
                    tokens.append(.keyword("minus"))
                    advance()
                }
            case "*":
                tokens.append(.keyword("times"))
                advance()
            case "/":
                tokens.append(.keyword("divide"))
                advance()
            default:
                if char.isLetter {
                    let word = readWhile { $0.isLetter }
                    if word == "true" {
                        tokens.append(.boolean(true))
                    } else if word == "false" {
                        tokens.append(.boolean(false))
                    } else if word == "null" {
                        tokens.append(.null)
                    } else if keywords.contains(word) {
                        tokens.append(.keyword(word))
                    } else {
                        tokens.append(.identifier(word))
                    }
                } else if char.isNumber {
                    let numStr = readWhile { $0.isNumber || $0 == "." }
                    if let num = Double(numStr) {
                        tokens.append(.number(num))
                    } else {
                        throw LexerError.invalidNumber(numStr)
                    }
                } else {
                    throw LexerError.unexpectedCharacter(char)
                }
            }
        }
        
        return tokens
    }
    
    private func peek() -> Character? {
            position < input.endIndex ? input[position] : nil
        }
    
    private func advance() {
            position = input.index(after: position)
        }
    
    private func readWhile(_ condition: (Character) -> Bool) -> String {
            var result = ""
            while let c = peek(), condition(c) {
                result.append(c)
                advance()
            }
            return result
        }
    
    private func peekNext() -> Character? {
        let nextIndex = input.index(after: position)
        return nextIndex < input.endIndex ? input[nextIndex] : nil
    }
}

enum LexerError: Error, CustomStringConvertible {
    case invalidNumber(String)
    case unexpectedCharacter(Character)
    
    var description: String {
        switch self {
        case .invalidNumber(let s): return "Invalid number literal: \(s)"
        case .unexpectedCharacter(let c): return "Unexpected character: \(c)"
        }
    }
}
