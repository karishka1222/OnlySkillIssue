import Foundation
import FInterpreter

print("Type code and press Enter (Ctrl+D to exit).!")

while let line = readLine() {
    do {
        let lexer = Lexer(input: line)
        let tokens = try lexer.tokenize()
        print(tokens)
    } catch {
        print("Lexer error: \(error)")
    }
}
