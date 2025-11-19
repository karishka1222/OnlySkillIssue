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
            
            // Syntax errors
            if !parser.errors.isEmpty {
                print("⚠️ Found \(parser.errors.count) syntax errors:")
                for err in parser.errors {
                    print("  \(err)")
                }
                print("")
            }
            
            // If AST is empty — skip semantic analysis
            guard !program.isEmpty else {
                print("❌ No valid AST nodes parsed, skipping semantic analysis.\n")
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
            let errors = analyzer.analyze()
            
            if errors.isEmpty {
                print("✅ No semantic errors found.\n")
                print("🚀 Running interpreter...\n")
                let interpreter = Interpreter()
                print("Result:")
                let results = try interpreter.interpret(nodes: program)
                for r in results {
                    print(r)
                }
            } else {
                print("⚠️ Found \(errors.count) semantic errors:")
                for err in errors {
                    print("  \(err)")
                }
                print("")
            }
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
            let lexer = Lexer(input: buffer + "\n")
            let tokens = lexer.tokenize()
            let parser = Parser(tokens: tokens, lenient: false)
            
            var program = parser.parseProgram()
            
            // Syntax errors
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
                print("🔹 AST before optimization:")
                for node in program {
                    print(node.element.prettyDescription())
                }
                
                if optimizeAST {
                    program = ASTOptimizer.optimizeProgram(program)
                    print("\n✅ AST after optimization:")
                    for node in program {
                        print(node.element.prettyDescription())
                    }
                } else {
                    print("\n⚙️ Optimization disabled.")
                }
                
                print("\n🔍 Running semantic analysis...\n")
                let analyzer = SemanticAnalyzer(ast: program)
                let errors = analyzer.analyze()
                
                if errors.isEmpty {
                    print("✅ No semantic errors found.\n")
                    print("🚀 Running interpreter...\n")
                    let interpreter = Interpreter()
                    do {
                        let value = try interpreter.interpret(nodes: program)
                        print("Result: \(value)\n")
                    } catch {
                        print("❌ Runtime error: \(error)\n")
                    }
                } else {
                    print("⚠️ Found \(errors.count) semantic errors:")
                    for err in errors {
                        print("  \(err)")
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
