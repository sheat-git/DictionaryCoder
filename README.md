# DictionaryCoder

A Swift library to serialize `Codable` to and from `[String: DictionaryValue]`.

## Usage

```swift
struct User {
    let id: Int
    let name: String
    let age: Int?
}

let encoder = DictionaryEncoder()

let user0 = User(id: 0, name: "sheat")
let dictionary0 = try! encoder.encode(user0) as! [String: DictionaryValue]
// -> ["id": 0, "name": "sheat"]

let user1 = User(id: 1, name: "sheat", age: 21)
let dictionary1 = try! encoder.encode(user1) as! [String: DictionaryValue]
// -> ["id": 1, "name": "sheat", age: 21]


let decoder = DictionaryDecoder()

let _user0 = try! decoder.decode(User.self, from: dictionary0)
// -> User(id: 0, name: "sheat", age: nil)

let _user1 = try! decoder.decode(User.self, from: dictionary1)
// -> User(id: 1, name: "sheat", age: 21)
```

## DictionaryValue

This protocol applies to

- `Bool`
- `Int`
- `Double`
- `Decimal`
- `String`
- `Array` (`Element == DictionaryValue?`)
- `Dictionary` (`Key == String, Value == DictionaryValue?`)

## EncodingStrategy / DecodingStrategy

The following options are available and can be used in the same way as JSONEncoder / JSONDecoder.

- DateEncodingStrategy / DateDecodingStrategy
- DataEncodingStrategy / DataDecodingStrategy
- KeyEncodingStrategy / KeyDecodingStrategy
