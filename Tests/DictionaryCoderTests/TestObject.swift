import Foundation

struct TestObject: Codable, Equatable {
    let bool: Bool
    let int: Int
    let int8: Int8
    let double: Double
    let float: Float
    let decimal: Decimal
    let string: String
    let array: [String]
    let object: TestObject2
    
    let date: Date
    let data: Data
    let url: URL
    
    let camelValue: String
    let optional: String?
    
    static let example: Self = .init(
        bool: true,
        int: 64,
        int8: 8,
        double: 0.5,
        float: 0.5,
        decimal: 0.1,
        string: "String",
        array: ["String0", "String1"],
        object: .init(value: "String"),
        date: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2001, month: 5, day: 30))!,
        data: Data(base64Encoded: "abcdefg=")!,
        url: URL(string: "https://google.com")!,
        camelValue: "camel",
        optional: nil
    )
}

struct TestObject2: Codable, Equatable {
    let value: String
}
