//
//  DictionaryEncoder.swift
//  
//
//  Created by sheat on 2023/01/17.
//

import Foundation

open class DictionaryEncoder {
    // MARK: Options
    
    /// The strategy to use for encoding `Date` values.
    public enum DateEncodingStrategy {
        /// Defer to `Date` for choosing an encoding. This is the default strategy.
        case deferredToDate
        
        /// Encode the `Date` as a UNIX timestamp (as a JSON number).
        case secondsSince1970
        
        /// Encode the `Date` as UNIX millisecond timestamp (as a JSON number).
        case millisecondsSince1970
        
        /// Encode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601
        
        /// Encode the `Date` as a string formatted by the given formatter.
        case formatted(DateFormatter)
        
        /// Encode the `Date` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Date, Encoder) throws -> Void)
    }
    
    /// The strategy to use for encoding `Data` values.
    public enum DataEncodingStrategy {
        /// Defer to `Data` for choosing an encoding.
        case deferredToData
        
        /// Encoded the `Data` as a Base64-encoded string. This is the default strategy.
        case base64
        
        /// Encode the `Data` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Data, Encoder) throws -> Void)
    }
    
    /// The strategy to use for automatically changing the value of keys before encoding.
    public enum KeyEncodingStrategy {
        /// Use the keys specified by each type. This is the default strategy.
        case useDefaultKeys
        
        /// Convert from "camelCaseKeys" to "snake_case_keys" before writing a key to JSON payload.
        ///
        /// Capital characters are determined by testing membership in `CharacterSet.uppercaseLetters` and `CharacterSet.lowercaseLetters` (Unicode General Categories Lu and Lt).
        /// The conversion to lower case uses `Locale.system`, also known as the ICU "root" locale. This means the result is consistent regardless of the current user's locale and language preferences.
        ///
        /// Converting from camel case to snake case:
        /// 1. Splits words at the boundary of lower-case to upper-case
        /// 2. Inserts `_` between words
        /// 3. Lowercases the entire string
        /// 4. Preserves starting and ending `_`.
        ///
        /// For example, `oneTwoThree` becomes `one_two_three`. `_oneTwoThree_` becomes `_one_two_three_`.
        ///
        /// - Note: Using a key encoding strategy has a nominal performance cost, as each string key has to be converted.
        case convertToSnakeCase
        
        /// Provide a custom conversion to the key in the encoded JSON from the keys specified by the encoded types.
        /// The full path to the current encoding position is provided for context (in case you need to locate this key within the payload). The returned key is used in place of the last component in the coding path before encoding.
        /// If the result of the conversion is a duplicate key, then only one value will be present in the result.
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
        
        fileprivate static func _convertToSnakeCase(_ stringKey: String) -> String {
            guard !stringKey.isEmpty else { return stringKey }
            
            var words: [Range<String.Index>] = []
            // The general idea of this algorithm is to split words on transition from lower to upper case, then on transition of >1 upper case characters to lowercase
            //
            // myProperty -> my_property
            // myURLProperty -> my_url_property
            //
            // We assume, per Swift naming conventions, that the first character of the key is lowercase.
            var wordStart = stringKey.startIndex
            var searchRange = stringKey.index(after: wordStart)..<stringKey.endIndex
            
            // Find next uppercase character
            while let upperCaseRange = stringKey.rangeOfCharacter(from: CharacterSet.uppercaseLetters, options: [], range: searchRange) {
                let untilUpperCase = wordStart..<upperCaseRange.lowerBound
                words.append(untilUpperCase)
                
                // Find next lowercase character
                searchRange = upperCaseRange.lowerBound..<searchRange.upperBound
                guard let lowerCaseRange = stringKey.rangeOfCharacter(from: CharacterSet.lowercaseLetters, options: [], range: searchRange) else {
                    // There are no more lower case letters. Just end here.
                    wordStart = searchRange.lowerBound
                    break
                }
                
                // Is the next lowercase letter more than 1 after the uppercase? If so, we encountered a group of uppercase letters that we should treat as its own word
                let nextCharacterAfterCapital = stringKey.index(after: upperCaseRange.lowerBound)
                if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
                    // The next character after capital is a lower case character and therefore not a word boundary.
                    // Continue searching for the next upper case for the boundary.
                    wordStart = upperCaseRange.lowerBound
                } else {
                    // There was a range of >1 capital letters. Turn those into a word, stopping at the capital before the lower case character.
                    let beforeLowerIndex = stringKey.index(before: lowerCaseRange.lowerBound)
                    words.append(upperCaseRange.lowerBound..<beforeLowerIndex)
                    
                    // Next word starts at the capital before the lowercase we just found
                    wordStart = beforeLowerIndex
                }
                searchRange = lowerCaseRange.upperBound..<searchRange.upperBound
            }
            words.append(wordStart..<searchRange.upperBound)
            let result = words.map({ (range) in
                return stringKey[range].lowercased()
            }).joined(separator: "_")
            return result
        }
    }

    /// The strategy to use in encoding dates. Defaults to `.deferredToDate`.
    open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate

    /// The strategy to use in encoding binary data. Defaults to `.base64`.
    open var dataEncodingStrategy: DataEncodingStrategy = .base64

    /// The strategy to use for encoding keys. Defaults to `.useDefaultKeys`.
    open var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys

    /// Contextual user-provided information for use during encoding.
    open var userInfo: [CodingUserInfoKey: Any] = [:]
    
    /// Options set on the top-level encoder to pass down the encoding hierarchy.
    fileprivate struct _Options {
        let dateEncodingStrategy: DateEncodingStrategy
        let dataEncodingStrategy: DataEncodingStrategy
        let keyEncodingStrategy: KeyEncodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }
    
    /// The options set on the top-level encoder.
    fileprivate var options: _Options {
        return _Options(
            dateEncodingStrategy: dateEncodingStrategy,
            dataEncodingStrategy: dataEncodingStrategy,
            keyEncodingStrategy: keyEncodingStrategy,
            userInfo: userInfo
        )
    }
    
    // MARK: - Constructing a Dictionary Encoder
    
    /// Initializes `self` with default strategies.
    public init() {}
    
    // MARK: - Encoding Values
    
    open func encode<T: Encodable>(_ value: T) throws -> DictionaryValue? {
        let encoder = DictionaryEncoderImpl(options: self.options, codingPath: [])
        guard let topLevel = try encoder.wrapEncodable(value, for: nil) else {
            throw EncodingError.invalidValue(value, .init(
                codingPath: [],
                debugDescription: "Top-level \(T.self) did not encode any values."
            ))
        }
        
        return topLevel
    }
}

// MARK: - _DictionaryEncoder

private enum DictionaryFuture {
    case value(DictionaryValue?)
    case encoder(DictionaryEncoderImpl)
    case nestedArray(RefArray)
    case nestedObject(RefObject)
    
    class RefArray {
        private(set) var array: [DictionaryFuture] = []
        
        init() {
            self.array.reserveCapacity(10)
        }
        
        @inline(__always) func append(_ element: DictionaryValue?) {
            self.array.append(.value(element))
        }
        
        @inline(__always) func append(_ encoder: DictionaryEncoderImpl) {
            self.array.append(.encoder(encoder))
        }
        
        @inline(__always) func appendArray() -> RefArray {
            let array = RefArray()
            self.array.append(.nestedArray(array))
            return array
        }
        
        @inline(__always) func appendObject() -> RefObject {
            let object = RefObject()
            self.array.append(.nestedObject(object))
            return object
        }
        
        var values: [DictionaryValue?] {
            self.array.map { (future) -> DictionaryValue? in
                switch future {
                case .value(let value):
                    return value
                case .nestedArray(let array):
                    return array.values
                case .nestedObject(let object):
                    return object.values
                case .encoder(let encoder):
                    return encoder.value ?? [:]
                }
            }
        }
    }
    
    class RefObject {
        private(set) var dict: [String: DictionaryFuture] = [:]
        
        init() {
            self.dict.reserveCapacity(20)
        }
        
        @inline(__always) func set(_ value: DictionaryValue?, for key: String) {
            self.dict[key] = .value(value)
        }
        
        @inline(__always) func setArray(for key: String) -> RefArray {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray(let array):
                return array
            case .none, .value:
                let array = RefArray()
                dict[key] = .nestedArray(array)
                return array
            }
        }
        
        @inline(__always) func setObject(for key: String) -> RefObject {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject(let object):
                return object
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .none, .value:
                let object = RefObject()
                dict[key] = .nestedObject(object)
                return object
            }
        }
        
        @inline(__always) func set(_ encoder: DictionaryEncoderImpl, for key: String) {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .none, .value:
                dict[key] = .encoder(encoder)
            }
        }
        
        var values: [String: DictionaryValue?] {
            self.dict.mapValues { (future) -> DictionaryValue? in
                switch future {
                case .value(let value):
                    return value
                case .nestedArray(let array):
                    return array.values
                case .nestedObject(let object):
                    return object.values
                case .encoder(let encoder):
                    return encoder.value ?? [:]
                }
            }
        }
    }
}

private class DictionaryEncoderImpl {
    let codingPath: [CodingKey]
    let options: DictionaryEncoder._Options
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }
    
    var singleValue: DictionaryValue??
    var object: DictionaryFuture.RefObject?
    var array: DictionaryFuture.RefArray?
    
    var value: DictionaryValue?? {
        if let object {
            return object.values
        }
        if let array {
            return array.values
        }
        return self.singleValue
    }
    
    init(options: DictionaryEncoder._Options, codingPath: [CodingKey]) {
        self.options = options
        self.codingPath = codingPath
    }
}

extension DictionaryEncoderImpl: Encoder {
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        if let _ = object {
            let container = DictionaryKeyedEncodingContainer<Key>(impl: self, codingPath: codingPath)
            return KeyedEncodingContainer(container)
        }
        
        guard self.singleValue == nil, self.array == nil else {
            preconditionFailure()
        }

        self.object = DictionaryFuture.RefObject()
        let container = DictionaryKeyedEncodingContainer<Key>(impl: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        if let _ = array {
            return DictionaryUnkeyedEncodingContainer(impl: self, codingPath: self.codingPath)
        }
        
        guard self.singleValue == nil, self.object == nil else {
            preconditionFailure()
        }
        
        self.array = DictionaryFuture.RefArray()
        return DictionaryUnkeyedEncodingContainer(impl: self, codingPath: self.codingPath)
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        DictionarySingleValueEncodingContainer(impl: self, codingPath: self.codingPath)
    }
}

// this is a private protocol to implement convenience methods directly on the EncodingContainers

extension DictionaryEncoderImpl: _SpecialTreatmentEncoder {
    var impl: DictionaryEncoderImpl {
        return self
    }

    // untyped escape hatch. needed for `wrapObject`
    func wrapUntyped(_ encodable: Encodable) throws -> DictionaryValue? {
        switch encodable {
        case let date as Date:
            return try self.wrapDate(date, for: nil)
        case let data as Data:
            return try self.wrapData(data, for: nil)
        case let url as URL:
            return url.absoluteString
        case let decimal as Decimal:
            return decimal
        default:
            try encodable.encode(to: self)
            return self.value ?? [:]
        }
    }
}

private protocol _SpecialTreatmentEncoder {
    var codingPath: [CodingKey] { get }
    var options: DictionaryEncoder._Options { get }
    var impl: DictionaryEncoderImpl { get }
}

extension _SpecialTreatmentEncoder {
    @inline(__always) fileprivate func wrapFloat<F: BinaryFloatingPoint>(_ float: F, for additionalKey: CodingKey?) throws -> DictionaryValue? {
        Double(float)
    }
    
    fileprivate func wrapEncodable<E: Encodable>(_ encodable: E, for additionalKey: CodingKey?) throws -> DictionaryValue?? {
        switch encodable {
        case let date as Date:
            return try self.wrapDate(date, for: additionalKey)
        case let data as Data:
            return try self.wrapData(data, for: additionalKey)
        case let url as URL:
            return url.absoluteString
        case let decimal as Decimal:
            return decimal
        default:
            let encoder = self.getEncoder(for: additionalKey)
            try encodable.encode(to: encoder)
            return encoder.value
        }
    }
    
    func wrapDate(_ date: Date, for additionalKey: CodingKey?) throws -> DictionaryValue? {
        switch self.options.dateEncodingStrategy {
        case .deferredToDate:
            let encoder = self.getEncoder(for: additionalKey)
            try date.encode(to: encoder)
            return encoder.value ?? nil
            
        case .secondsSince1970:
            return date.timeIntervalSince1970
            
        case .millisecondsSince1970:
            return date.timeIntervalSince1970 * 1000
            
        case .iso8601:
            if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                return _iso8601Formatter.string(from: date)
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }
            
        case .formatted(let formatter):
            return formatter.string(from: date)
            
        case .custom(let closure):
            let encoder = self.getEncoder(for: additionalKey)
            try closure(date, encoder)
            // The closure didn't encode anything. Return the default keyed container.
            return encoder.value ?? [:]
        }
    }
    
    func wrapData(_ data: Data, for additionalKey: CodingKey?) throws -> DictionaryValue? {
        switch self.options.dataEncodingStrategy {
        case .deferredToData:
            let encoder = self.getEncoder(for: additionalKey)
            try data.encode(to: encoder)
            return encoder.value ?? nil
            
        case .base64:
            let base64 = data.base64EncodedString()
            return base64
            
        case .custom(let closure):
            let encoder = self.getEncoder(for: additionalKey)
            try closure(data, encoder)
            // The closure didn't encode anything. Return the default keyed container.
            return encoder.value ?? [:]
        }
    }
    
    fileprivate func getEncoder(for additionalKey: CodingKey?) -> DictionaryEncoderImpl {
        if let additionalKey = additionalKey {
            var newCodingPath = self.codingPath
            newCodingPath.append(additionalKey)
            return DictionaryEncoderImpl(options: self.options, codingPath: newCodingPath)
        }
        
        return self.impl
    }
}

private struct DictionaryKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol, _SpecialTreatmentEncoder {
    typealias Key = K
    
    let impl: DictionaryEncoderImpl
    let codingPath: [CodingKey]
    let object: DictionaryFuture.RefObject
    
    private var firstValueWritten: Bool = false
    fileprivate var options: DictionaryEncoder._Options {
        self.impl.options
    }
    
    init(impl: DictionaryEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.codingPath = codingPath
        self.object = impl.object!
    }
    
    // used for nested containers
    init(impl: DictionaryEncoderImpl, object: DictionaryFuture.RefObject, codingPath: [CodingKey]) {
        self.impl = impl
        self.object = object
        self.codingPath = codingPath
    }
    
    private func _converted(_ key: Key) -> CodingKey {
        switch self.impl.options.keyEncodingStrategy {
        case .useDefaultKeys:
            return key
        case .convertToSnakeCase:
            let newKeyString = DictionaryEncoder.KeyEncodingStrategy._convertToSnakeCase(key.stringValue)
            return DictionaryCodingKey(stringValue: newKeyString, intValue: key.intValue)
        case .custom(let converter):
            return converter(codingPath + [key])
        }
    }
    
    mutating func encodeNil(forKey key: K) throws {
        self.object.set(nil, for: self._converted(key).stringValue)
    }
    
    mutating func encode(_ value: Bool, forKey key: K) throws {
        self.object.set(value, for: self._converted(key).stringValue)
    }
    
    mutating func encode(_ value: String, forKey key: K) throws {
        self.object.set(value, for: self._converted(key).stringValue)
    }
    
    mutating func encode(_ value: Double, forKey key: K) throws {
        try encodeFloatingPoint(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: Float, forKey key: K) throws {
        try encodeFloatingPoint(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: Int, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: Int8, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: Int16, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: Int32, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: Int64, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: UInt, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: UInt8, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: UInt16, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: UInt32, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode(_ value: UInt64, forKey key: K) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }
    
    mutating func encode<T>(_ value: T, forKey key: K) throws where T : Encodable {
        let convertedKey = self._converted(key)
        let encoded = try self.wrapEncodable(value, for: convertedKey)
        self.object.set(encoded ?? [:], for: convertedKey.stringValue)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        let convertedKey = self._converted(key)
        let newPath = self.codingPath + [convertedKey]
        let object = self.object.setObject(for: convertedKey.stringValue)
        let nestedContainer = DictionaryKeyedEncodingContainer<NestedKey>(impl: impl, object: object, codingPath: newPath)
        return KeyedEncodingContainer(nestedContainer)
    }
    
    mutating func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        let convertedKey = self._converted(key)
        let newPath = self.codingPath + [convertedKey]
        let array = self.object.setArray(for: convertedKey.stringValue)
        let nestedContainer = DictionaryUnkeyedEncodingContainer(impl: impl, array: array, codingPath: newPath)
        return nestedContainer
    }
    
    mutating func superEncoder() -> Encoder {
        let newEncoder = self.getEncoder(for: DictionaryCodingKey.super)
        self.object.set(newEncoder, for: DictionaryCodingKey.super.stringValue)
        return newEncoder
    }
    
    mutating func superEncoder(forKey key: K) -> Encoder {
        let convertedKey = self._converted(key)
        let newEncoder = self.getEncoder(for: convertedKey)
        self.object.set(newEncoder, for: convertedKey.stringValue)
        return newEncoder
    }
}

extension DictionaryKeyedEncodingContainer {
    @inline(__always) private mutating func encodeFloatingPoint<F: BinaryFloatingPoint>(_ float: F, key: CodingKey) throws {
        let value = try self.wrapFloat(float, for: key)
        self.object.set(value, for: key.stringValue)
    }

    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N, key: CodingKey) throws {
        self.object.set(Int(value), for: key.stringValue)
    }
}

private struct DictionaryUnkeyedEncodingContainer: UnkeyedEncodingContainer, _SpecialTreatmentEncoder {
    let impl: DictionaryEncoderImpl
    let array: DictionaryFuture.RefArray
    let codingPath: [CodingKey]

    var count: Int {
        self.array.array.count
    }
    private var firstValueWritten: Bool = false
    fileprivate var options: DictionaryEncoder._Options {
        return self.impl.options
    }

    init(impl: DictionaryEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.array = impl.array!
        self.codingPath = codingPath
    }

    // used for nested containers
    init(impl: DictionaryEncoderImpl, array: DictionaryFuture.RefArray, codingPath: [CodingKey]) {
        self.impl = impl
        self.array = array
        self.codingPath = codingPath
    }
    
    mutating func encodeNil() throws {
        self.array.append(nil)
    }

    mutating func encode(_ value: Bool) throws {
        self.array.append(value)
    }

    mutating func encode(_ value: String) throws {
        self.array.append(value)
    }

    mutating func encode(_ value: Double) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: Float) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: Int) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        let key = DictionaryCodingKey(stringValue: "Index \(self.count)", intValue: self.count)
        let encoded = try self.wrapEncodable(value, for: key)
        self.array.append(encoded ?? [:])
    }

    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) ->
        KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
    {
        let newPath = self.codingPath + [DictionaryCodingKey(index: self.count)]
        let object = self.array.appendObject()
        let nestedContainer = DictionaryKeyedEncodingContainer<NestedKey>(impl: impl, object: object, codingPath: newPath)
        return KeyedEncodingContainer(nestedContainer)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let newPath = self.codingPath + [DictionaryCodingKey(index: self.count)]
        let array = self.array.appendArray()
        let nestedContainer = DictionaryUnkeyedEncodingContainer(impl: impl, array: array, codingPath: newPath)
        return nestedContainer
    }

    mutating func superEncoder() -> Encoder {
        let encoder = self.getEncoder(for: DictionaryCodingKey(index: self.count))
        self.array.append(encoder)
        return encoder
    }
}

extension DictionaryUnkeyedEncodingContainer {
    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N) throws {
        self.array.append(Int(value))
    }

    @inline(__always) private mutating func encodeFloatingPoint<F: BinaryFloatingPoint>(_ float: F) throws {
        let value = try self.wrapFloat(float, for: DictionaryCodingKey(index: self.count))
        self.array.append(value)
    }
}

private struct DictionarySingleValueEncodingContainer: SingleValueEncodingContainer, _SpecialTreatmentEncoder {
    let impl: DictionaryEncoderImpl
    let codingPath: [CodingKey]

    private var firstValueWritten: Bool = false
    fileprivate var options: DictionaryEncoder._Options {
        return self.impl.options
    }

    init(impl: DictionaryEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .some(nil)
    }

    mutating func encode(_ value: Bool) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = value
    }

    mutating func encode(_ value: Int) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Float) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: Double) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: String) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = value
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = try self.wrapEncodable(value, for: nil)
    }

    func preconditionCanEncodeNewValue() {
        precondition(self.impl.singleValue == nil, "Attempt to encode value through single value container when previously value already encoded.")
    }
}

extension DictionarySingleValueEncodingContainer {
    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = Int(value)
    }

    @inline(__always) private mutating func encodeFloatingPoint<F: BinaryFloatingPoint>(_ float: F) throws {
        self.preconditionCanEncodeNewValue()
        let value = try self.wrapFloat(float, for: nil)
        self.impl.singleValue = value
    }
}
