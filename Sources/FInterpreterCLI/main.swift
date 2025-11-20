import Foundation
import FInterpreter

// MARK: - Run Tests from File
func runFileTests(optimizeAST: Bool) {
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
        print("🔧 AST optimization mode: \(optimizeAST ? "ON" : "OFF")\n")
        
        for (index, block) in blocks.enumerated() {
            print("──────────────────────────────────────────────")
            print("Test Block \(index + 1):\n\(block)\n")
            
            let lexer = Lexer(input: block + "\n")
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens, lenient: false)
            
            var program = parser.parseProgram()
            var hasErrors = false
            
            // Syntax errors - display, but continue
            if !parser.errors.isEmpty {
                print("⚠️ Found \(parser.errors.count) syntax errors:")
                for err in parser.errors {
                    print("  \(err)")
                }
                hasErrors = true
            }
            
            // If AST is empty, skip the remaining steps
            guard !program.isEmpty else {
                print("❌ No valid AST nodes parsed.\n")
                continue
            }
            
            
//            print("🔹 AST before optimization:")
            for node in program {
//                print(node.element.prettyDescription())
            }
            
            // AST optimization
            if optimizeAST {
                program = ASTOptimizer.optimizeProgram(program)
//                print("\n✅ AST after optimization:")
                for node in program {
//                    print(node.element.prettyDescription())
                }
            } else {
//                print("\n⚙️ Optimization disabled.")
            }
            
            
            print("\n🔍 Running semantic analysis...\n")
            let analyzer = SemanticAnalyzer(ast: program)
            let semanticErrors = analyzer.analyze()
            
            if semanticErrors.isEmpty {
                print("✅ No semantic errors found.\n")
            } else {
                print("⚠️ Found \(semanticErrors.count) semantic errors:")
                for err in semanticErrors {
                    print("  \(err)")
                }
                hasErrors = true
            }
            
            // Run the interpreter only if there are no errors at all
            if !hasErrors {
                print("🚀 Running interpreter...\n")
                let interpreter = Interpreter()
                print("Result:")
                let results = try interpreter.interpret(nodes: program)
                for r in results {
                    print(r)
                }
            } else {
                print("")
                print("❌ Skipping interpreter due to errors\n")
            }
            print("")
        }
        
        print("=== End of File Tests ===")
    } catch {
        print("❌ Could not read tests.txt: \(error)")
    }
}

// MARK: - Console Mode
func runConsoleTests(optimizeAST: Bool) {
    print("=== Console Mode ===")
    print("🔧 AST optimization mode: \(optimizeAST ? "ON" : "OFF")\n")
    print("Type code (multi-line allowed). Type ':run' to parse, ':quit' to exit.\n")
    
    var buffer = ""
    
    while let line = readLine() {
        if line == ":quit" {
            break
        } else if line == ":run" {
            guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("❌ No code to execute.\n")
                buffer = ""
                continue
            }
            
            let lexer = Lexer(input: buffer + "\n")
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens, lenient: false)
            
            var program = parser.parseProgram()
            var hasErrors = false
            
            // Syntax errors - display, but continue
            if !parser.errors.isEmpty {
                print("⚠️ Found \(parser.errors.count) syntax errors:")
                for err in parser.errors {
                    print("  \(err)")
                }
                hasErrors = true
            }
            
            // If AST is empty, skip the remaining steps
            guard !program.isEmpty else {
                print("❌ No valid AST nodes parsed.\n")
                buffer = ""
                continue
            }
            
            
//            print("🔹 AST before optimization:")
            for node in program {
//                print(node.element.prettyDescription())
            }
            
            // AST optimization
            if optimizeAST {
                program = ASTOptimizer.optimizeProgram(program)
//                print("\n✅ AST after optimization:")
                for node in program {
//                    print(node.element.prettyDescription())
                }
            } else {
//                print("\n⚙️ Optimization disabled.")
            }
            
            
            print("\n🔍 Running semantic analysis...\n")
            let analyzer = SemanticAnalyzer(ast: program)
            let semanticErrors = analyzer.analyze()
            
            if semanticErrors.isEmpty {
                print("✅ No semantic errors found.\n")
            } else {
                print("⚠️ Found \(semanticErrors.count) semantic errors:")
                for err in semanticErrors {
                    print("  \(err)")
                }
                hasErrors = true
            }
            
            // Run the interpreter only if there are no errors at all
            if !hasErrors {
                print("🚀 Running interpreter...\n")
                let interpreter = Interpreter()
                do {
                    let results = try interpreter.interpret(nodes: program)
                    print("Result:")
                    for r in results {
                        print(r)
                    }
                } catch {
                    print("❌ Runtime error: \(error)\n")
                }
            } else {
                print("")
                print("❌ Skipping interpreter due to errors\n")
            }
            
            buffer = ""
            print("")
        } else {
            buffer.append(line)
            buffer.append("\n")
        }
    }
    
    print("=== End of Console Mode ===")
}

// MARK: - Main Execution
print("Choose mode: 'txt' for file tests or 'console' for interactive mode.")
if let choice = readLine()?.lowercased() {
    print("Enable AST optimization? (yes/no)")
    let optChoice = readLine()?.lowercased() ?? "no"
    let optimize = (optChoice == "yes" || optChoice == "y")
    
    switch choice {
    case "txt":
        runFileTests(optimizeAST: optimize)
    case "console":
        runConsoleTests(optimizeAST: optimize)
    default:
        print("❌ Unknown option. Please run again and choose either 'txt' or 'console'.")
    }
}
