import Foundation
import FInterpreter

let fileManager = FileManager.default
let currentPath = fileManager.currentDirectoryPath
let filePath = "/Users/karinasiniatullina/innopolis/3 курс/CompilerConstriction/OnlySkillIssue/Tests/tests.txt"

do {
    let content = try String(contentsOfFile: filePath, encoding: .utf8)
    let lines = content
        .split(separator: "\n")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }

    print("=== Running FInterpreter Lexer Tests ===\n")

    for (index, line) in lines.enumerated() {
        print("Test \(index + 1): \(line)")
        do {
            let lexer = Lexer(input: line)
            let tokens = lexer.tokenize()
//            let result = tokens.map { token -> String in
//                switch token {
//                case .number(let n): return "\(n)"
//                case .boolean(let b): return "\(b)"
//                case .null: return "null"
//                case .identifier(let s): return s
//                case .keyword(let s): return s
//                case .quote: return "'"
//                case .lparen: return "("
//                case .rparen: return ")"
//                case .unknown(let s): return "\(s)"
//                }
//            }.joined(separator: " ")
            print("Tokens: \(tokens)\n")
        }
    }

    print("=== End of Tests ===")
} catch {
    print("Could not read tests.txt: \(error)")
}
