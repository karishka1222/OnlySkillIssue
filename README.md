### F Interpreter (Language F Compiler/Interpreter)

_Functional Lisp-like language implementation for Compiler Construction course_

---

### Project Description

This project implements an interpreter (with compilation-like stages) for **Language F** – a small, functional, Lisp-like language used in a Compiler Construction course.  
The toolchain takes an F program, runs it through **lexical analysis**, **parsing**, **AST optimization**, **semantic analysis**, and finally **interprets** the program.

The implementation is written in **Swift** as a Swift Package and provides:

- **Library**: `FInterpreter` – reusable components (Lexer, Parser, AST, Optimizer, Semantic Analyzer, Interpreter)
- **CLI tool**: `FInterpreterCLI` – command-line interface to run file-based tests or an interactive console

---

### Features

- **Full front-end pipeline**:
  - Lexer for Language F tokens (literals, identifiers, keywords, parentheses, quote, etc.)
  - Recursive-descent Parser building an AST (`Element` + `Node` with line numbers)
  - AST pretty-printing (tree-like structure) for debugging
- **AST optimization**:
  - Constant folding for arithmetic, comparison and logical expressions
  - Simple dead code elimination for unused `setq` assignments
- **Semantic analysis**:
  - Symbol table with nested scopes for variables and functions
  - Checks for:
    - Use of undeclared identifiers/functions
    - Argument count mismatches for user-defined and built-in functions
    - Type checks for arithmetic, comparisons, logical operations, list operations, `cond`, `while`, etc.
    - Correct usage of `quote`, `setq`, `func`, `lambda`, `prog`, `cond`, `while`, `return`, `break`
- **Interpreter**:
  - Support for all **special forms**: `quote`, `setq`, `func`, `lambda`, `prog`, `cond`, `while`, `return`, `break`
  - Support for all **predefined functions** from the specification:
    - Arithmetic: `plus`, `minus`, `times`, `divide`
    - Lists: `head`, `tail`, `cons`
    - Comparisons: `equal`, `nonequal`, `less`, `lesseq`, `greater`, `greatereq`
    - Predicates: `isint`, `isreal`, `isbool`, `isnull`, `isatom`, `islist`
    - Logical: `and`, `or`, `xor`, `not`
    - Evaluator: `eval`
  - Proper handling of user-defined functions and lambdas with closures
  - `prog` and `while` with `return` and `break` control-flow
- **CLI modes**:
  - Running predefined test suites from `tests.txt`
  - Interactive REPL-like console mode for entering F code

---

### Project Structure

- **`Package.swift`** – Swift Package definition (library + executable + tests)
- **`Sources/FInterpreter/`**
  - `Lexer.swift` – tokenization of Language F
  - `Parser.swift` – AST construction with error recovery and pretty-print
  - `ASTOptimizer.swift` – constant folding and simple dead code elimination
  - `SemanticAnalyzer.swift` – symbol table and static checks
  - `Interpreter.swift` – runtime environment, values, special forms, built-ins
- **`Sources/FInterpreterCLI/`**
  - `main.swift` – CLI entry point; interactive console and file-based test runner
  - `Resources/tests.txt` – sample programs and error cases for testing
- **`Tests/FInterpreterTests.swift`** – unit tests for the interpreter components

---

### Installation

There are **two ways** to run the project: via **Xcode** and via **Swift Package Manager in the terminal**. Both are valid; the terminal way is just an alternative for those who prefer running without Xcode.

#### Option 1: Xcode (recommended)

- Open the `.xcodeproj` or `Package.swift` in Xcode.
- Select the `FInterpreterCLI` scheme.
- Press **Build and then Run current scheme**.
- In the Xcode console:
  - type `txt` to run all examples from `tests.txt`, or `console` to enter interactive mode;
  - then answer `yes`/`no` to the `Enable AST optimization?` question.

In `txt` mode the CLI:

- tokenizes and prints input tokens;
- builds and prints the AST (before and optionally after optimization);
- runs semantic analysis and prints semantic errors (if any);
- if there are no syntax/semantic errors, interprets the program and prints results.

In `console` mode:

- you can type multi-line F programs;
- use `:run` to execute the current buffer and `:quit` to exit;
- for each execution, tokens, AST, semantic analysis and final results are printed in the console.

#### Option 2: Terminal with SwiftPM (alternative)

- Make sure **Swift** with SwiftPM support is installed.  
  Official guide: `https://www.swift.org/getting-started/`

- Clone the repository:

  ```bash
  git clone https://github.com/karishka1222/OnlySkillIssue.git
  cd OnlySkillIssue
  ```

- Build:

  ```bash
  swift build
  ```

- Run the CLI:

  ```bash
  swift run FInterpreterCLI
  ```

  After that the behavior is the same as in Xcode:

  - type `txt` to run tests from `tests.txt`;
  - type `console` to enter interactive mode;
  - answer `yes`/`no` to `Enable AST optimization? (yes/no)`.

---

### Short Overview of Language F

Language F is a small functional language inspired by Lisp:

- **Program structure**:
  - A program is a sequence of **Elements**.
  - **Elements** are:
    - Atoms (identifiers)
    - Literals (integers, reals, booleans, `null`)
    - Lists (parenthesized sequences of elements)
- **Evaluation model**:
  - Literals evaluate to themselves.
  - Atoms evaluate to their bound value (unless quoted).
  - A list is treated as a function call:
    - First element – function name (or special form keyword)
    - Remaining elements – arguments

#### Special Forms

Special forms have reserved keywords and custom evaluation rules:

- `quote`, `'` – prevent evaluation of the argument, e.g. `'x`, `'(1 2 3)`
- `setq` – variable assignment: `(setq x (plus 1 2))`
- `func` – named user-defined functions:  
  `(func Cube (arg) (times (times arg arg) arg))`
- `lambda` – anonymous functions:  
  `(lambda (p) (cond (less p 0) plus minus))`
- `prog` – block with local variables and sequential execution
- `cond` – conditional evaluation (2 or 3 arguments)
- `while` – loop with boolean condition
- `return` – exit from nearest `func`, `lambda` or `prog` with a value
- `break` – exit from nearest `while`

#### Predefined Functions

- **Arithmetic**: `plus`, `minus`, `times`, `divide`
- **List operations**: `head`, `tail`, `cons`
- **Comparisons**: `equal`, `nonequal`, `less`, `lesseq`, `greater`, `greatereq`
- **Predicates**: `isint`, `isreal`, `isbool`, `isnull`, `isatom`, `islist`
- **Logical**: `and`, `or`, `xor`, `not`
- **Evaluator**: `eval` – evaluates a value as code if it is a list

#### Grammar (Informal)

- Program: one or more `Element`s
- List: `( Element ... )`
- Element: `Atom | Literal | List`
- Literals:
  - Integers and reals (with optional sign)
  - Booleans: `true | false`
  - `null`
- Identifiers:
  - Start with a letter
  - Followed by letters or decimal digits

---

### Frameworks and Technologies

- **Swift** – implementation language
- **Swift Package Manager (SPM)** – build system and dependency manager
- **Xcode** (optional) – project files included for IDE support

