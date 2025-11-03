import Foundation
import FInterpreter

func runFileTests() {
    guard let fileURL = Bundle.module.url(forResource: "tests", withExtension: "txt") else {
        print("❌ Could not find tests.txt in resources.")
        return
    }
    
    do {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        
        let rawBlocks = content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let blocks = rawBlocks.map { block in
            block
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
                .joined(separator: "\n")
        }.filter { !$0.isEmpty }
        
        print("=== Running FInterpreter Tests from file ===\n")
        
        for (index, block) in blocks.enumerated() {
            print("Test Block \(index + 1):\n\(block)\n")
            
            let lexer = Lexer(input: block + "\n")
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens, lenient: false)
            
            let program = parser.parseProgram()
            
            // 🔸 Выводим синтаксические ошибки, если есть
            if !parser.errors.isEmpty {
                print("⚠️ Found \(parser.errors.count) syntax errors:")
                for err in parser.errors {
                    print("  \(err)")
                }
                print("")
            }
            
            // 🔸 Если AST пуст — пропускаем семантический анализ
            guard !program.isEmpty else {
                print("❌ No valid AST nodes parsed, skipping semantic analysis.\n")
                continue
            }
            
            print("AST:")
            for node in program {
                print(node.element.prettyDescription())
            }
            
            print("\n🔍 Running semantic analysis...\n")
            let analyzer = SemanticAnalyzer(ast: program)
            let errors = analyzer.analyze()
            
            if errors.isEmpty {
                print("✅ No semantic errors found.\n")
            } else {
                for err in errors {
                    print("❌ \(err)")
                }
                print("")
            }
        }
        
        print("=== End of File Tests ===")
    } catch {
        print("❌ Could not read tests.txt: \(error)")
    }
}


func runConsoleTests() {
    print("=== Console Mode ===")
    print("Type code (multi-line allowed). Type ':run' to parse, ':quit' to exit.")
    
    var buffer = ""
    
    while let line = readLine() {
        if line == ":quit" {
            break
        } else if line == ":run" {
            let lexer = Lexer(input: buffer + "\n")
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens, lenient: false)
            
            let program = parser.parseProgram()
            
            // 🔸 Выводим синтаксические ошибки
            if !parser.errors.isEmpty {
                print("⚠️ Found \(parser.errors.count) syntax errors:")
                for err in parser.errors {
                    print("  \(err)")
                }
                print("")
            }
            
            if program.isEmpty {
                print("❌ No valid AST nodes parsed.\n")
            } else {
                print("AST:")
                for node in program {
                    print(node.element.prettyDescription())
                }
                
                print("\n🔍 Running semantic analysis...\n")
                let analyzer = SemanticAnalyzer(ast: program)
                let errors = analyzer.analyze()
                
                if errors.isEmpty {
                    print("✅ No semantic errors found.\n")
                } else {
                    for err in errors {
                        print("❌ \(err)")
                    }
                    print("")
                }
            }
            
            buffer = ""
        } else {
            buffer.append(line)
            buffer.append("\n")
        }
    }
    
    print("=== End of Console Mode ===")
}

// Entry point
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
