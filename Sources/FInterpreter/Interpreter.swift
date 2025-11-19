import Foundation

// MARK: - Interpreter Error
public enum InterpreterError: Error, CustomStringConvertible, Sendable {
    case typeMismatch(String)
    case undefinedAtom(String)
    case argumentCount(String)
    case returnValue(Value)
    case breakSignal
    case generic(String)
    
    public var description: String {
        switch self {
        case .typeMismatch(let msg): return "Type mismatch: \(msg)"
        case .undefinedAtom(let name): return "Undefined atom: \(name)"
        case .argumentCount(let msg): return "Argument count error: \(msg)"
        case .returnValue(let v): return "Return signal with value: \(v)"
        case .breakSignal: return "Break signal"
        case .generic(let msg): return "Interpreter error: \(msg)"
        }
    }
}

// MARK: - Runtime Values
public indirect enum Value: CustomStringConvertible, @unchecked Sendable {
    case integer(Int)
    case real(Double)
    case boolean(Bool)
    case null
    case atom(String)
    case list([Value])
    case function(Function)

    public var description: String {
        switch self {
        case .integer(let i): return "\(i)"
        case .real(let r): return "\(r)"
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "null"
        case .atom(let a): return a
        case .list(let l): return "(\(l.map { $0.description }.joined(separator: " ")))"
        case .function: return "<function>"
        }
    }
}

// MARK: - Function Representation
public struct Function: @unchecked Sendable {
    let params: [String]
    let body: Element
    let env: Environment // closure
}

// MARK: - Environment
public class Environment: @unchecked Sendable {
    private var store: [String: Value] = [:]
    private var outer: Environment?

    init(outer: Environment? = nil) {
        self.outer = outer
    }

    func set(_ name: String, value: Value) {
        store[name] = value
    }

    func get(_ name: String) -> Value? {
        if let v = store[name] { return v }
        return outer?.get(name)
    }

    func contains(_ name: String) -> Bool {
        return store[name] != nil || outer?.contains(name) == true
    }
}

// MARK: - Interpreter
public class Interpreter {
    private let globalEnv = Environment()

    public init() {}

    public func interpret(nodes: [Node]) throws -> [Value] {
        var results: [Value] = []

        for node in nodes {
            let result = try eval(node.element, env: globalEnv)

            // Убираем вывод для while, func, setq
            if case .list(let elems) = node.element,
               let first = elems.first,
               case .atom(let fname) = first,
               (fname == "while" || fname == "func" || fname == "setq")
            {
                continue
            }

            results.append(result)
        }

        return results
    }

    private func eval(_ element: Element, env: Environment) throws -> Value {
        switch element {
        case .integer(let i): return .integer(i)
        case .real(let r): return .real(r)
        case .boolean(let b): return .boolean(b)
        case .null: return .null
        case .atom(let name):
            if let v = env.get(name) { return v }
            throw InterpreterError.undefinedAtom(name)
        case .list(let elems):
            guard let first = elems.first else { return .null }
            switch first {

            case .atom(let fname):
                // спецформы и builtins остаются как есть
                switch fname {
                case "quote": return try quote(elems)
                case "setq": return try setq(elems, env: env)
                case "func": return try defineFunc(elems, env: env)
                case "lambda": return try defineLambda(elems, env: env)
                case "prog": return try prog(elems, env: env)
                case "cond": return try cond(elems, env: env)
                case "while": return try whileLoop(elems, env: env)
                case "return":
                    let val = try eval(elems[1], env: env)
                    throw InterpreterError.returnValue(val)
                case "break": throw InterpreterError.breakSignal
                default:
                    return try callFunction(fname, args: Array(elems.dropFirst()), env: env)
                }

            default:
                // ВЫЗОВ ЛЯМБДЫ ИЛИ ФУНКЦИИ, ЗАПИСАННОЙ В ПЕРЕМЕННОЙ
                let op = try eval(first, env: env)
                guard case .function(let f) = op else {
                    throw InterpreterError.typeMismatch("First element of list is not a function")
                }

                let evaluatedArgs = try Array(elems.dropFirst()).map { try eval($0, env: env) }
                guard evaluatedArgs.count == f.params.count else {
                    throw InterpreterError.argumentCount("Function expects \(f.params.count) arguments")
                }

                let localEnv = Environment(outer: f.env)
                for (param, val) in zip(f.params, evaluatedArgs) {
                    localEnv.set(param, value: val)
                }

                do {
                    return try eval(f.body, env: localEnv)
                } catch InterpreterError.returnValue(let v) {
                    return v
                }
            }
        }
    }

    // MARK: - Special Forms
    private func quote(_ elems: [Element]) throws -> Value {
        guard elems.count == 2 else { throw InterpreterError.argumentCount("quote expects 1 argument") }
        return elementToValue(elems[1])
    }

    private func setq(_ elems: [Element], env: Environment) throws -> Value {
        guard elems.count == 3 else { throw InterpreterError.argumentCount("setq expects 2 arguments") }
        guard case .atom(let name) = elems[1] else { throw InterpreterError.typeMismatch("First argument of setq must be atom") }
        let value = try eval(elems[2], env: env)
        env.set(name, value: value)
        return value
    }

    private func defineFunc(_ elems: [Element], env: Environment) throws -> Value {
        guard elems.count == 4 else { throw InterpreterError.argumentCount("func expects 3 arguments") }
        guard case .atom(let name) = elems[1] else { throw InterpreterError.typeMismatch("Function name must be atom") }
        guard case .list(let paramsElems) = elems[2] else { throw InterpreterError.typeMismatch("Function parameters must be a list") }
        let params = try paramsElems.map { elem -> String in
            if case .atom(let a) = elem { return a }
            else { throw InterpreterError.typeMismatch("Parameter must be an atom") }
        }
        let function = Function(params: params, body: elems[3], env: env)
        env.set(name, value: .function(function))
        return .function(function)
    }

    private func defineLambda(_ elems: [Element], env: Environment) throws -> Value {
        guard elems.count == 3 else { throw InterpreterError.argumentCount("lambda expects 2 arguments") }
        guard case .list(let paramsElems) = elems[1] else { throw InterpreterError.typeMismatch("Lambda parameters must be a list") }
        let params = try paramsElems.map { elem -> String in
            if case .atom(let a) = elem { return a }
            else { throw InterpreterError.typeMismatch("Parameter must be an atom") }
        }
        let function = Function(params: params, body: elems[2], env: env)
        return .function(function)
    }

    private func prog(_ elems: [Element], env: Environment) throws -> Value {
        // elems: [ "prog", locals-list, stmt1, stmt2, ... ]
        guard elems.count >= 2 else {
            throw InterpreterError.argumentCount("prog expects at least 1 argument list of locals")
        }
        guard case .list(let localAtoms) = elems[1] else {
            throw InterpreterError.typeMismatch("prog first argument must be list of atoms")
        }

        let localEnv = Environment(outer: env)

        // Declare locals
        for atom in localAtoms {
            if case .atom(let name) = atom {
                localEnv.set(name, value: .null)
            } else {
                throw InterpreterError.typeMismatch("prog locals must be atoms")
            }
        }

        // Evaluate body expressions from elems[2...]
        var result: Value = .null
        for stmt in elems.dropFirst(2) {
            do {
                result = try eval(stmt, env: localEnv)
            } catch InterpreterError.returnValue(let v) {
                return v
            } catch InterpreterError.breakSignal {
                throw InterpreterError.breakSignal
            }
        }

        return result
    }

    private func cond(_ elems: [Element], env: Environment) throws -> Value {
        guard elems.count == 3 || elems.count == 4 else { throw InterpreterError.argumentCount("cond expects 2 or 3 arguments") }
        let test = try eval(elems[1], env: env)
        guard let condBool = asBoolOptional(test) else { throw InterpreterError.typeMismatch("cond expects boolean condition, got \(test)") }
        if condBool {
            return try eval(elems[2], env: env)
        } else if elems.count == 4 {
            return try eval(elems[3], env: env)
        } else {
            return .null
        }
    }

    private func whileLoop(_ elems: [Element], env: Environment) throws -> Value {
        // elems: ["while", cond, stmt1, stmt2, ...]
        guard elems.count >= 3 else {
            throw InterpreterError.argumentCount("while expects condition and at least 1 body expression")
        }

        var result: Value = .null

        while true {
            let condVal = try eval(elems[1], env: env)
            guard let condBool = asBoolOptional(condVal) else {
                throw InterpreterError.typeMismatch("while expects boolean condition, got \(condVal)")
            }
            if !condBool { break }

            // Выполняем все выражения тела по одному
            for stmt in elems.dropFirst(2) {
                do {
                    result = try eval(stmt, env: env)
                } catch InterpreterError.breakSignal {
                    return .null
                } catch InterpreterError.returnValue(let v) {
                    throw InterpreterError.returnValue(v)
                }
            }
        }

        return result
    }

    // MARK: - Function Calls and Builtins
    private func callFunction(_ name: String, args: [Element], env: Environment) throws -> Value {
        let evaluatedArgs = try args.map { try eval($0, env: env) }

        // User-defined functions
        if let val = env.get(name), case .function(let funcObj) = val {
            guard evaluatedArgs.count == funcObj.params.count else {
                throw InterpreterError.argumentCount("Function \(name) expects \(funcObj.params.count) arguments")
            }
            let localEnv = Environment(outer: funcObj.env)
            for (param, arg) in zip(funcObj.params, evaluatedArgs) {
                localEnv.set(param, value: arg)
            }
            do {
                return try eval(funcObj.body, env: localEnv)
            } catch InterpreterError.returnValue(let v) {
                return v
            }
        }

        // Built-in functions
        return try callBuiltin(name, args: evaluatedArgs, env: env)
    }

    // MARK: - Built-in Functions
    private func callBuiltin(_ name: String, args: [Value], env: Environment) throws -> Value {
        switch name {
        case "plus":     return try arithBinary(args, op: +)
        case "minus":    return try arithBinary(args, op: -)
        case "times":    return try arithBinary(args, op: *)
        case "divide":   return try arithBinary(args, op: /)
        case "less":     return try compareBinary(args, op: <)
        case "lesseq":   return try compareBinary(args, op: <=)
        case "greater":  return try compareBinary(args, op: >)
        case "greatereq":return try compareBinary(args, op: >=)
        case "equal":    return try equalBinary(args, op: ==)
        case "nonequal": return try equalBinary(args, op: !=)
        case "isint":    return try isTypeUnary(args, matches: { if case .integer = $0 { return true } else { return false } })
        case "isreal":   return try isTypeUnary(args, matches: { if case .real = $0 { return true } else { return false } })
        case "isbool":   return try isTypeUnary(args, matches: { if case .boolean = $0 { return true } else { return false } })
        case "isnull":   return try isTypeUnary(args, matches: { if case .null = $0 { return true } else { return false } })
        case "isatom":   return try isTypeUnary(args, matches: { if case .atom = $0 { return true } else { return false } })
        case "islist":   return try isTypeUnary(args, matches: { if case .list = $0 { return true } else { return false } })
        case "and":      return try boolBinary(args, op: { $0 && $1 })
        case "or":       return try boolBinary(args, op: { $0 || $1 })
        case "xor":      return try boolBinary(args, op: { $0 != $1 })
        case "not":      return try boolUnary(args, op: { !$0 })
        case "head":     return try headOp(args)
        case "tail":     return try tailOp(args)
        case "cons":     return try consOp(args)
        case "eval":     return try evalOp(args, env: env)
        default:
            throw InterpreterError.generic("Unknown function \(name)")
        }
    }

    // MARK: - Arithmetic, Comparisons, Logic
    private func arithBinary(_ args: [Value], op: (Double, Double) -> Double) throws -> Value {
        guard args.count == 2 else { throw InterpreterError.argumentCount("Arithmetic expects 2 arguments") }
        let a = try asNumber(args[0])
        let b = try asNumber(args[1])
        let res = op(a, b)
        return res.truncatingRemainder(dividingBy: 1) == 0 ? .integer(Int(res)) : .real(res)
    }

    private func compareBinary(_ args: [Value], op: (Double, Double) -> Bool) throws -> Value {
        guard args.count == 2 else { throw InterpreterError.argumentCount("Comparison expects 2 arguments") }
        let a = try asNumericOrBool(args[0])
        let b = try asNumericOrBool(args[1])
        return .boolean(op(a, b))
    }

    private func equalBinary(_ args: [Value], op: (Double, Double) -> Bool) throws -> Value {
        guard args.count == 2 else { throw InterpreterError.argumentCount("Equal expects 2 arguments") }
        let a = try asNumericOrBool(args[0])
        let b = try asNumericOrBool(args[1])
        return .boolean(op(a, b))
    }

    private func asNumber(_ val: Value) throws -> Double {
        switch val {
        case .integer(let i): return Double(i)
        case .real(let r): return r
        default: throw InterpreterError.typeMismatch("Expected number, got \(val)")
        }
    }

    private func asNumericOrBool(_ val: Value) throws -> Double {
        switch val {
        case .integer(let i): return Double(i)
        case .real(let r): return r
        case .boolean(let b): return b ? 1.0 : 0.0
        default: throw InterpreterError.typeMismatch("Expected number or boolean, got \(val)")
        }
    }

    private func isTypeUnary(_ args: [Value], matches: (Value) -> Bool) throws -> Value {
        guard args.count == 1 else { throw InterpreterError.argumentCount("Predicate expects 1 argument") }
        return .boolean(matches(args[0]))
    }

    private func boolBinary(_ args: [Value], op: (Bool, Bool) -> Bool) throws -> Value {
        guard args.count == 2 else { throw InterpreterError.argumentCount("Boolean expects 2 arguments") }
        let a = try asBool(args[0])
        let b = try asBool(args[1])
        return .boolean(op(a, b))
    }

    private func boolUnary(_ args: [Value], op: (Bool) -> Bool) throws -> Value {
        guard args.count == 1 else { throw InterpreterError.argumentCount("Boolean expects 1 argument") }
        let a = try asBool(args[0])
        return .boolean(op(a))
    }

    private func asBool(_ val: Value) throws -> Bool {
        if case .boolean(let b) = val { return b }
        throw InterpreterError.typeMismatch("Expected boolean, got \(val)")
    }

    private func asBoolOptional(_ val: Value) -> Bool? {
        if case .boolean(let b) = val { return b }
        return nil
    }

    // MARK: - List Operations
    private func headOp(_ args: [Value]) throws -> Value {
        guard args.count == 1 else { throw InterpreterError.argumentCount("head expects 1 argument") }
        if case .list(let arr) = args[0], let first = arr.first { return first }
        throw InterpreterError.typeMismatch("head expects non-empty list")
    }

    private func tailOp(_ args: [Value]) throws -> Value {
        guard args.count == 1 else { throw InterpreterError.argumentCount("tail expects 1 argument") }
        if case .list(let arr) = args[0] { return .list(Array(arr.dropFirst())) }
        throw InterpreterError.typeMismatch("tail expects list")
    }

    private func consOp(_ args: [Value]) throws -> Value {
        guard args.count == 2 else { throw InterpreterError.argumentCount("cons expects 2 arguments") }
        if case .list(let tail) = args[1] { return .list([args[0]] + tail) }
        throw InterpreterError.typeMismatch("cons expects list as second argument")
    }

    private func evalOp(_ args: [Value], env: Environment) throws -> Value {
        guard args.count == 1 else { throw InterpreterError.argumentCount("eval expects 1 argument") }
        switch args[0] {
        case .list(let l):
            return try eval(valueToElement(.list(l)), env: env)
        default: return args[0]
        }
    }

    // MARK: - Helpers
    private func elementToValue(_ e: Element) -> Value {
        switch e {
        case .integer(let i): return .integer(i)
        case .real(let r): return .real(r)
        case .boolean(let b): return .boolean(b)
        case .null: return .null
        case .atom(let a): return .atom(a)
        case .list(let l): return .list(l.map { elementToValue($0) })
        }
    }

    private func valueToElement(_ v: Value) -> Element {
        switch v {
        case .integer(let i): return .integer(i)
        case .real(let r): return .real(r)
        case .boolean(let b): return .boolean(b)
        case .null: return .null
        case .atom(let a): return .atom(a)
        case .list(let l): return .list(l.map { valueToElement($0) })
        case .function: return .atom("<function>")
        }
    }
}

