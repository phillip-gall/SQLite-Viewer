import XCTest
@testable import SQLite_Viewer

@MainActor
final class RowFilterEditorModelTests: XCTestCase {
    private let columns = [
        RowColumn(id: 0, name: "id", declaredType: "INTEGER"),
        RowColumn(id: 1, name: "payload", declaredType: "BLOB")
    ]

    func testIntegerPrecisionAndInvalidValueRecovery() throws {
        let model = RowFilterEditorModel(columns: columns, editing: nil)
        model.enteredValue = "9223372036854775807"
        XCTAssertEqual(try XCTUnwrap(model.makeFilter()).value, .integer(Int64.max))
        model.enteredValue = "9223372036854775808"
        XCTAssertNil(model.makeFilter())
        XCTAssertNotNil(model.errorMessage)
        model.enteredValue = "12"
        XCTAssertEqual(try XCTUnwrap(model.makeFilter()).value, .integer(12))
        XCTAssertNil(model.errorMessage)
    }

    func testBlobOnlyAllowsNullChecksAndEditingPreservesIdentity() throws {
        let original = RowFilter(column: "payload", operation: .isNull)
        let model = RowFilterEditorModel(columns: columns, editing: original)
        XCTAssertEqual(try XCTUnwrap(model.makeFilter()).id, original.id)
        model.operation = .equals
        model.enteredValue = "123"
        XCTAssertNil(model.makeFilter())
        model.operation = .isNotNull
        XCTAssertNil(try XCTUnwrap(model.makeFilter()).value)
    }

    func testNonFiniteRealAndNumericContainsAreRejected() {
        let model = RowFilterEditorModel(columns: columns, editing: nil)
        model.valueKind = .real
        model.enteredValue = "nan"
        XCTAssertNil(model.makeFilter())
        model.enteredValue = "1.5"
        model.operation = .contains
        XCTAssertNil(model.makeFilter())
    }
}
