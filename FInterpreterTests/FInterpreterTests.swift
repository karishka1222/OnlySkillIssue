import XCTest
@testable import FInterpreter

final class FInterpreterTests: XCTestCase {

    private func run(_ program: String) throws -> String {
        let interpreter = Interpreter()
        let value = try interpreter.evaluate(program: program)
        return String(describing: value)
    }

    // 1. Literals and simple assignment
    func testLiteralsAndSetq() throws {
        XCTAssertEqual(try run("42"), "42")
        XCTAssertEqual(try run("-7"), "-7")
        XCTAssertEqual(try run("3.14"), "3.14")
        XCTAssertEqual(try run("true"), "true")
        XCTAssertEqual(try run("null"), "null")
        XCTAssertEqual(try run("(setq x 5) x"), "5")
    }

    // 2. quote and lists
    func testQuoteAndLists() throws {
        XCTAssertEqual(try run("'x"), "x")
        XCTAssertEqual(try run("(setq t '(plus minus times divide)) t"), "(plus minus times divide)")
    }

    // 3. arithmetic
    func testArithmetic() throws {
        XCTAssertEqual(try run("(plus 1 2)"), "3")
        XCTAssertEqual(try run("(minus 5 2)"), "3")
        XCTAssertEqual(try run("(times 3 4)"), "12")
        XCTAssertEqual(try run("(divide 3 2)"), "1.5")
    }

    // 4. comparisons and predicates
    func testComparisonsAndPredicates() throws {
        XCTAssertEqual(try run("(less 1 2)"), "true")
        XCTAssertEqual(try run("(equal 1 1)"), "true")
        XCTAssertEqual(try run("(isint 3)"), "true")
        XCTAssertEqual(try run("(isreal 3.0)"), "true")
        XCTAssertEqual(try run("(isatom 'x)"), "true")
        XCTAssertEqual(try run("(islist '(1 2 3))"), "true")
        XCTAssertEqual(try run("(isnull null)"), "true")
    }

    // 5. head / tail / cons
    func testListOperations() throws {
        XCTAssertEqual(try run("(head '(a b c))"), "a")
        XCTAssertEqual(try run("(tail '(a b c))"), "(b c)")
        XCTAssertEqual(try run("(cons 1 '(2 3))"), "(1 2 3)")
    }

    // 6. logical operators
    func testLogicalOperators() throws {
        XCTAssertEqual(try run("(and true false)"), "false")
        XCTAssertEqual(try run("(or true false)"), "true")
        XCTAssertEqual(try run("(xor true false)"), "true")
        XCTAssertEqual(try run("(not true)"), "false")
    }

    // 7. func / lambda / calls
    func testFuncAndLambda() throws {
        XCTAssertEqual(try run("(func inc (x) (plus x 1)) (inc 5)"), "6")
        XCTAssertEqual(try run("(setq f (lambda (x) (times x x))) (f 4)"), "16")
        XCTAssertEqual(try run("((lambda (x y) (plus x y)) 3 4)"), "7")
    }

    // 8. prog, local scope and return
    func testProgScopeAndReturn() throws {
        XCTAssertEqual(try run("(prog (a b) (setq a 1) (setq b (plus a 2)) (plus a b))"), "4")
        XCTAssertEqual(try run("(func test () (prog (a) (setq a 1) (return 99) 5)) (test)"), "99")
    }

    // 9. cond and while
    func testCondAndWhile() throws {
        XCTAssertEqual(try run("(cond (less 2 1) 10 20)"), "20")
        XCTAssertEqual(try run("(cond (less 1 2) 100)"), "100")
        XCTAssertEqual(try run("(prog (i) (setq i 0) (while (less i 3) (setq i (plus i 1))) i)"), "3")
    }

    // 10. break inside while
    func testBreakInWhile() throws {
        XCTAssertEqual(try run("(prog (i) (setq i 0) (while (less i 10) (setq i (plus i 1)) (cond (greater i 3) (break))) i)"), "4")
    }

    // 11. eval
    func testEval() throws {
        XCTAssertEqual(try run("(eval '(plus 1 2))"), "3")
        XCTAssertEqual(try run("(eval 5)"), "5")
        XCTAssertEqual(try run("(eval 'x)"), "x")
    }

    // 12. recursion: factorial
    func testRecursionFactorial() throws {
        XCTAssertEqual(try run("(func fact (n) (cond (less n 2) 1 (times n (fact (minus n 1))))) (fact 5)"), "120")
    }

    // 13. closures (if language supports capture)
    func testClosures() throws {
        XCTAssertEqual(try run("(prog () (setq maker (lambda (x) (lambda () x))) (setq f (maker 5)) (f))"), "5")
    }

    // 14. type error: plus with boolean and number
    func testTypeError() throws {
        XCTAssertThrowsError(try run("(plus true 1)"))
    }

    // 15. argument evaluation order and side effects (left-to-right)
    func testEvaluationOrderAndSideEffects() throws {
        XCTAssertEqual(try run("(prog (a) (setq a 0) (plus (setq a (plus a 1)) (setq a (plus a 2))) a)"), "3")
    }
}
