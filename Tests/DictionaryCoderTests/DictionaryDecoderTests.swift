import XCTest
@testable import DictionaryCoder

final class DictionaryDecoderTests: XCTestCase {
    func testDateSecondesSince1970() throws {
        let decoder = DictionaryDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let value: Double = 10
        let date = try decoder.decode(Date.self, from: value)
        XCTAssertEqual(date.timeIntervalSince1970, 10)
    }
    
    func testDateMilliSecondsSince1970() throws {
        let decoder = DictionaryDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value: Double = 10 * 1000
        let date = try decoder.decode(Date.self, from: value)
        XCTAssertEqual(date.timeIntervalSince1970, 10)
    }
    
    func testObject() throws {
        let decoder = DictionaryDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value: [String: DictionaryValue?] = [
            "bool": true,
            "int": Int(64),
            "int8": Int(8),
            "double": Double(0.5),
            "float": Double(0.5),
            "decimal": Decimal(0.1),
            "string": "String",
            "array": ["String0", "String1"],
            "object": ["value": "String"],
            "date": "2001-05-30T00:00:00+09:00",
            "data": "abcdefg=",
            "url": "https://google.com",
            "camel_value": "camel"
        ]
        let object = try decoder.decode(TestObject.self, from: value)
        XCTAssertEqual(object, TestObject.example)
    }
}
