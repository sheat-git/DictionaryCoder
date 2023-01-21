import XCTest
@testable import DictionaryCoder

final class DictionaryEncoderTests: XCTestCase {
    func testNil() throws {
        let encoder = DictionaryEncoder()
        let value: String? = nil
        XCTAssertNil(try encoder.encode(value))
    }
    
    func testObject() throws {
        let encoder = DictionaryEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let dictionary = try encoder.encode(TestObject.example) as! [String: DictionaryValue?]
        XCTAssertTrue(dictionary["bool"] as! Bool)
        XCTAssertEqual(dictionary["int"] as! Int, Int(64))
        XCTAssertEqual(dictionary["int8"] as! Int, Int(8))
        XCTAssertEqual(dictionary["double"] as! Double, Double(0.5))
        XCTAssertEqual(dictionary["float"] as! Double, Double(0.5))
        XCTAssertEqual(dictionary["decimal"] as! Decimal, Decimal(0.1))
        XCTAssertEqual(dictionary["string"] as! String, "String")
        XCTAssertEqual(dictionary["array"] as! [String], ["String0", "String1"])
        XCTAssertEqual((dictionary["object"] as! [String: DictionaryValue?])["value"] as! String, "String")
        XCTAssertEqual(dictionary["date"] as! String, "2001-05-29T15:00:00Z")
        XCTAssertEqual(dictionary["data"] as! String, "abcdefg=")
        XCTAssertEqual(dictionary["url"] as! String, "https://google.com")
        XCTAssertEqual(dictionary["camel_value"] as! String, "camel")
    }
}
