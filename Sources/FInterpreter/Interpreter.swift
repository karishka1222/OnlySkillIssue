import Foundation

// MARK: - Interpreter Error
public enum InterpreterError: Error, CustomStringConvertible, Sendable {
    case returnValue(Value)
    case breakSignal
    
    public var description: String {
        switch self {
        case .returnValue(let v): return "Return signal with value: \(v)"
        case .breakSignal: return "Break signal"
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

            // Remove the output for while, func, setq
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
            return env.get(name)!
        case .list(let elems):
            guard let first = elems.first else { return .null }
            switch first {

            case .atom(let fname):
                // special forms and builtins remain unchanged
                switch fname {
                case "quote": return quote(elems)
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
                // call lambda or function stored in variable
                let op = try eval(first, env: env)
                let f: Function
                if case .function(let funcObj) = op {
                    f = funcObj
                } else {
                    return .null
                }

                let evaluatedArgs = try Array(elems.dropFirst()).map { try eval($0, env: env) }

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
    private func quote(_ elems: [Element]) -> Value {
        return elementToValue(elems[1])
    }

    private func setq(_ elems: [Element], env: Environment) throws -> Value {
        let name: String
        if case .atom(let atomName) = elems[1] {
            name = atomName
        } else {
            return .null
        }
        let value = try eval(elems[2], env: env)
        env.set(name, value: value)
        return value
    }

    private func defineFunc(_ elems: [Element], env: Environment) throws -> Value {
        let name: String
        if case .atom(let atomName) = elems[1] {
            name = atomName
        } else {
            return .null
        }
        
        let paramsElems: [Element]
        if case .list(let p) = elems[2] {
            paramsElems = p
        } else {
            return .null
        }
        
        let params = paramsElems.map { elem -> String in
            if case .atom(let a) = elem { return a }
            else { return "" }
        }
        let function = Function(params: params, body: elems[3], env: env)
        env.set(name, value: .function(function))
        return .function(function)
    }

    private func defineLambda(_ elems: [Element], env: Environment) throws -> Value {
        let paramsElems: [Element]
        if case .list(let p) = elems[1] {
            paramsElems = p
        } else {
            return .null
        }
        
        let params = paramsElems.map { elem -> String in
            if case .atom(let a) = elem { return a }
            else { return "" }
        }
        let function = Function(params: params, body: elems[2], env: env)
        return .function(function)
    }

    private func prog(_ elems: [Element], env: Environment) throws -> Value {
        let localAtoms: [Element]
        if case .list(let l) = elems[1] {
            localAtoms = l
        } else {
            return .null
        }

        let localEnv = Environment(outer: env)

        // Declare locals
        for atom in localAtoms {
            if case .atom(let name) = atom {
                localEnv.set(name, value: .null)
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
        let test = try eval(elems[1], env: env)
        if let condBool = asBoolOptional(test), condBool {
            return try eval(elems[2], env: env)
        } else if elems.count == 4 {
            return try eval(elems[3], env: env)
        } else {
            return .null
        }
    }

    private func whileLoop(_ elems: [Element], env: Environment) throws -> Value {
        var result: Value = .null

        while true {
            let condVal = try eval(elems[1], env: env)
            if let condBool = asBoolOptional(condVal), !condBool { break }

            // execute all expressions in the body one by one
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

        // user-defined functions
        if let val = env.get(name), case .function(let funcObj) = val {
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

        // built-in functions
        return try callBuiltin(name, args: evaluatedArgs, env: env)
    }

    // MARK: - Built-in Functions
    private func callBuiltin(_ name: String, args: [Value], env: Environment) throws -> Value {
        switch name {
        case "plus":     return arithBinary(args, op: +)
        case "minus":    return arithBinary(args, op: -)
        case "times":    return arithBinary(args, op: *)
        case "divide":   return arithBinary(args, op: /)
        case "less":     return compareBinary(args, op: <)
        case "lesseq":   return compareBinary(args, op: <=)
        case "greater":  return compareBinary(args, op: >)
        case "greatereq":return compareBinary(args, op: >=)
        case "equal":    return equalBinary(args, op: ==)
        case "nonequal": return equalBinary(args, op: !=)
        case "isint":    return isTypeUnary(args, matches: { if case .integer = $0 { return true } else { return false } })
        case "isreal":   return isTypeUnary(args, matches: { if case .real = $0 { return true } else { return false } })
        case "isbool":   return isTypeUnary(args, matches: { if case .boolean = $0 { return true } else { return false } })
        case "isnull":   return isTypeUnary(args, matches: { if case .null = $0 { return true } else { return false } })
        case "isatom":   return isTypeUnary(args, matches: { if case .atom = $0 { return true } else { return false } })
        case "islist":   return isTypeUnary(args, matches: { if case .list = $0 { return true } else { return false } })
        case "and":      return boolBinary(args, op: { $0 && $1 })
        case "or":       return boolBinary(args, op: { $0 || $1 })
        case "xor":      return boolBinary(args, op: { $0 != $1 })
        case "not":      return boolUnary(args, op: { !$0 })
        case "head":     return headOp(args)
        case "tail":     return tailOp(args)
        case "cons":     return consOp(args)
        case "eval":     return try evalOp(args, env: env)
        default:
            return .null
        }
    }

    // MARK: - Arithmetic, Comparisons, Logic
    private func arithBinary(_ args: [Value], op: (Double, Double) -> Double) -> Value {
        let a = asNumber(args[0])
        let b = asNumber(args[1])
        let res = op(a, b)
        return res.truncatingRemainder(dividingBy: 1) == 0 ? .integer(Int(res)) : .real(res)
    }

    private func compareBinary(_ args: [Value], op: (Double, Double) -> Bool) -> Value {
        let a = asNumericOrBool(args[0])
        let b = asNumericOrBool(args[1])
        return .boolean(op(a, b))
    }

    private func equalBinary(_ args: [Value], op: (Double, Double) -> Bool) -> Value {
        let a = asNumericOrBool(args[0])
        let b = asNumericOrBool(args[1])
        return .boolean(op(a, b))
    }

    private func asNumber(_ val: Value) -> Double {
        switch val {
        case .integer(let i): return Double(i)
        case .real(let r): return r
        default: return 0.0
        }
    }

    private func asNumericOrBool(_ val: Value) -> Double {
        switch val {
        case .integer(let i): return Double(i)
        case .real(let r): return r
        case .boolean(let b): return b ? 1.0 : 0.0
        default: return 0.0
        }
    }

    private func isTypeUnary(_ args: [Value], matches: (Value) -> Bool) -> Value {
        return .boolean(matches(args[0]))
    }

    private func boolBinary(_ args: [Value], op: (Bool, Bool) -> Bool) -> Value {
        let a = asBool(args[0])
        let b = asBool(args[1])
        return .boolean(op(a, b))
    }

    private func boolUnary(_ args: [Value], op: (Bool) -> Bool) -> Value {
        let a = asBool(args[0])
        return .boolean(op(a))
    }

    private func asBool(_ val: Value) -> Bool {
        if case .boolean(let b) = val { return b }
        return false
    }

    private func asBoolOptional(_ val: Value) -> Bool? {
        if case .boolean(let b) = val { return b }
        return nil
    }

    // MARK: - List Operations
    private func headOp(_ args: [Value]) -> Value {
        if case .list(let arr) = args[0], let first = arr.first { return first }
        return .null
    }

    private func tailOp(_ args: [Value]) -> Value {
        if case .list(let arr) = args[0] { return .list(Array(arr.dropFirst())) }
        return .null
    }

    private func consOp(_ args: [Value]) -> Value {
        if case .list(let tail) = args[1] { return .list([args[0]] + tail) }
        return .null
    }

    private func evalOp(_ args: [Value], env: Environment) throws -> Value {
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
