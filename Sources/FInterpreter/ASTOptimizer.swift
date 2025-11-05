import Foundation

public final class ASTOptimizer {
    /// Главная точка входа: оптимизация списка узлов (программа)
    public static func optimizeProgram(_ nodes: [Node]) -> [Node] {
        // Сначала рекурсивно оптимизируем узлы (constant folding внутри выражений)
        var optimizedNodes = nodes.map { optimizeNode($0) }
        // Затем удаляем неиспользуемые переменные (dead setq elimination)
        optimizedNodes = removeUnusedVariables(optimizedNodes)
        return optimizedNodes
    }

    /// Упрощает отдельный узел
    private static func optimizeNode(_ node: Node) -> Node {
        let e = optimizeElement(node.element)
        return Node(element: e, line: node.line)
    }

    /// Рекурсивная оптимизация узла
    private static func optimizeElement(_ e: Element) -> Element {
        switch e {
        case .list(let elems):
            // Рекурсивно оптимизируем детей
            let optimizedChildren = elems.map { optimizeElement($0) }

            // Попытка свёртывания константных выражений
            if let folded = constantFold(optimizedChildren) {
                return folded
            }
            return .list(optimizedChildren)
        default:
            return e
        }
    }

    /// Простое свёртывание константных выражений
    private static func constantFold(_ elems: [Element]) -> Element? {
        guard elems.count >= 1 else { return nil }
        guard case .atom(let opName) = elems[0] else { return nil }

        // Нормализуем имя оператора (оставляем строчные буквы)
        let op = opName

        // ---- Арифметика (бинарные операции) ----
        let addNames = ["+", "plus"]
        let subNames = ["-", "minus"]
        let mulNames = ["*", "times"]
        let divNames = ["/", "divide"]

        if (addNames + subNames + mulNames + divNames).contains(op),
           elems.count == 3,
           let lhs = numericValue(of: elems[1]),
           let rhs = numericValue(of: elems[2]) {
            if addNames.contains(op) {
                let sum = lhs + rhs
                // Если результат целый — integer, иначе real
                if floor(sum) == sum { return .integer(Int(sum)) }
                return .real(sum)
            }
            if subNames.contains(op) {
                let res = lhs - rhs
                if floor(res) == res { return .integer(Int(res)) }
                return .real(res)
            }
            if mulNames.contains(op) {
                let res = lhs * rhs
                if floor(res) == res { return .integer(Int(res)) }
                return .real(res)
            }
            if divNames.contains(op) {
                if rhs == 0 { return nil } // избегаем деления на 0
                let res = lhs / rhs
                if floor(res) == res { return .integer(Int(res)) }
                return .real(res)
            }
        }

        // ---- Сравнения ----
        let lessNames = ["<", "less"]
        let leNames   = ["<=", "lesseq"]
        let greaterNames = [">", "greater"]
        let geNames = [">=", "greatereq"]
        let eqNames = ["=", "==", "equal"]
        let neqNames = ["nonequal"]

        if (lessNames + leNames + greaterNames + geNames + eqNames + neqNames).contains(op),
           elems.count == 3,
           let lhs = numericValue(of: elems[1]),
           let rhs = numericValue(of: elems[2]) {
            if lessNames.contains(op) { return .boolean(lhs < rhs) }
            if leNames.contains(op)   { return .boolean(lhs <= rhs) }
            if greaterNames.contains(op) { return .boolean(lhs > rhs) }
            if geNames.contains(op)   { return .boolean(lhs >= rhs) }
            if eqNames.contains(op)   { return .boolean(lhs == rhs) }
            if neqNames.contains(op)  { return .boolean(lhs != rhs) }
        }

        // ---- Логические операции ----
        if op == "not", elems.count == 2 {
            if case .boolean(let b) = elems[1] { return .boolean(!b) }
        }
        if op == "and", elems.count == 3 {
            if case .boolean(let a) = elems[1], case .boolean(let b) = elems[2] {
                return .boolean(a && b)
            }
        }
        if op == "or", elems.count == 3 {
            if case .boolean(let a) = elems[1], case .boolean(let b) = elems[2] {
                return .boolean(a || b)
            }
        }

        return nil
    }

    private static func numericValue(of e: Element) -> Double? {
        switch e {
        case .integer(let i): return Double(i)
        case .real(let r): return r
        case .boolean(let b): return b ? 1.0 : 0.0 // иногда удобно трактовать bool как 1/0
        default: return nil
        }
    }

    // -------------------------------------------------
    // Удаляет неиспользуемые переменные (только простые `setq`)
    // -------------------------------------------------
    private static func removeUnusedVariables(_ nodes: [Node]) -> [Node] {
        // Находим все объявления и все использования
        var declared: Set<String> = []
        var used: Set<String> = []

        func collect(element: Element) {
            switch element {
            case .atom(let s):
                used.insert(s)
            case .list(let elems):
                if elems.count >= 3,
                   case .atom("setq") = elems[0],
                   case .atom(let varName) = elems[1] {
                    // Регистрируем объявление переменной
                    declared.insert(varName)
                    // Рекурсивно собираем использованные идентификаторы в значении
                    collect(element: elems[2])
                } else {
                    // Общая рекурсия по дочерним узлам
                    elems.forEach { collect(element: $0) }
                }
            default:
                break
            }
        }

        for n in nodes { collect(element: n.element) }

        // Переменные, которые объявлены, но нигде не используются (за исключением их объявления)
        let unused = declared.subtracting(used)
        guard !unused.isEmpty else { return nodes }

        // Фильтруем узлы: удаляем верхнеуровневые setq для неиспользуемых переменных
        let filtered = nodes.filter {
            if case .list(let elems) = $0.element,
               elems.count >= 3,
               case .atom("setq") = elems[0],
               case .atom(let varName) = elems[1],
               unused.contains(varName) {
                return false
            }
            return true
        }

        return filtered
    }
}
