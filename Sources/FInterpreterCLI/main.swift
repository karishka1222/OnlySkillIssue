import Foundation
import FInterpreter

func runFileTests() {
    guard let fileURL = Bundle.module.url(forResource: "tests", withExtension: "txt") else {
        print("❌ Could not find tests.txt in resources.")
        return
    }
    
    do {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        
        print("=== Running FInterpreter Lexer Tests from file ===\n")
        
        for (index, line) in lines.enumerated() {
            print("Test \(index + 1): \(line)")
            let lexer = Lexer(input: line)
            let tokens = lexer.tokenize()
            print("Tokens: \(tokens)\n")
        }
        
        print("=== End of File Tests ===")
    } catch {
        print("❌ Could not read tests.txt: \(error)")
    }
}

func runConsoleTests() {
    print("=== Console Lexer Mode ===")
    print("Type code and press Enter (Ctrl+D to exit).")
    
    while let line = readLine() {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            continue
        }
        let lexer = Lexer(input: line)
        let tokens = lexer.tokenize()
        print("Tokens: \(tokens)")
    }
    
    print("=== End of Console Mode ===")
}

print("Choose mode: type 'txt' for file tests or 'console' for interactive mode.")
if let choice = readLine()?.lowercased() {
    switch choice {
    case "txt":
        runFileTests()
    case "console":
        runConsoleTests()
    default:
        print("❌ Unknown option. Please run again and choose either 'txt' or 'console'.")
    }
}
