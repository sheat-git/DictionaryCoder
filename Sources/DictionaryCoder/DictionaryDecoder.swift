//
//  DictionaryDecoder.swift
//  
//
//  Created by sheat on 2023/01/16.
//

import Foundation

open class DictionaryDecoder {
    // MARK: Options
    
    /// The strategy to use for decoding `Date` values.
    public enum DateDecodingStrategy {
        /// Defer to `Date` for decoding. This is the default strategy.
        case deferredToDate

        /// Decode the `Date` as a UNIX timestamp from a JSON number.
        case secondsSince1970

        /// Decode the `Date` as UNIX millisecond timestamp from a JSON number.
        case millisecondsSince1970

        /// Decode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601

        /// Decode the `Date` as a string parsed by the given formatter.
        case formatted(DateFormatter)

        /// Decode the `Date` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Date)
    }
    
    /// The strategy to use for decoding `Data` values.
    public enum DataDecodingStrategy {
        /// Defer to `Data` for decoding.
        case deferredToData

        /// Decode the `Data` from a Base64-encoded string. This is the default strategy.
        case base64

        /// Decode the `Data` as a custom value decoded by the given closure.
        case custom((_ decoder: Decoder) throws -> Data)
    }
    
    /// The strategy to use for automatically changing the value of keys before decoding.
    public enum KeyDecodingStrategy {
        /// Use the keys specified by each type. This is the default strategy.
        case useDefaultKeys
        
        /// Convert from "snake_case_keys" to "camelCaseKeys" before attempting to match a key with the one specified by each type.
        ///
        /// The conversion to upper case uses `Locale.system`, also known as the ICU "root" locale. This means the result is consistent regardless of the current user's locale and language preferences.
        ///
        /// Converting from snake case to camel case:
        /// 1. Capitalizes the word starting after each `_`
        /// 2. Removes all `_`
        /// 3. Preserves starting and ending `_` (as these are often used to indicate private variables or other metadata).
        /// For example, `one_two_three` becomes `oneTwoThree`. `_one_two_three_` becomes `_oneTwoThree_`.
        ///
        /// - Note: Using a key decoding strategy has a nominal performance cost, as each string key has to be inspected for the `_` character.
        case convertFromSnakeCase
        
        /// Provide a custom conversion from the key in the dictionary to the keys specified by the decoded types.
        /// The full path to the current decoding position is provided for context (in case you need to locate this key within the payload). The returned key is used in place of the last component in the coding path before decoding.
        /// If the result of the conversion is a duplicate key, then only one value will be present in the container for the type to decode from.
        case custom((_ codingPath: [CodingKey]) -> CodingKey)
        
        fileprivate static func _convertFromSnakeCase(_ stringKey: String) -> String {
            guard !stringKey.isEmpty else { return stringKey }
            
            // Find the first non-underscore character
            guard let firstNonUnderscore = stringKey.firstIndex(where: { $0 != "_" }) else {
                // Reached the end without finding an _
                return stringKey
            }
            
            // Find the last non-underscore character
            var lastNonUnderscore = stringKey.index(before: stringKey.endIndex)
            while lastNonUnderscore > firstNonUnderscore, stringKey[lastNonUnderscore] == "_" {
                stringKey.formIndex(before: &lastNonUnderscore)
            }
            
            let keyRange = firstNonUnderscore...lastNonUnderscore
            let leadingUnderscoreRange = stringKey.startIndex..<firstNonUnderscore
            let trailingUnderscoreRange = stringKey.index(after: lastNonUnderscore)..<stringKey.endIndex
            
            let components = stringKey[keyRange].split(separator: "_")
            let joinedString: String
            if components.count == 1 {
                // No underscores in key, leave the word as is - maybe already camel cased
                joinedString = String(stringKey[keyRange])
            } else {
                joinedString = ([components[0].lowercased()] + components[1...].map { $0.capitalized }).joined()
            }
            
            // Do a cheap isEmpty check before creating and appending potentially empty strings
            let result: String
            if leadingUnderscoreRange.isEmpty, trailingUnderscoreRange.isEmpty {
                result = joinedString
            } else if !leadingUnderscoreRange.isEmpty, !trailingUnderscoreRange.isEmpty {
                // Both leading and trailing underscores
                result = String(stringKey[leadingUnderscoreRange]) + joinedString + String(stringKey[trailingUnderscoreRange])
            } else if !leadingUnderscoreRange.isEmpty {
                // Just leading
                result = String(stringKey[leadingUnderscoreRange]) + joinedString
            } else {
                // Just trailing
                result = joinedString + String(stringKey[trailingUnderscoreRange])
            }
            return result
        }
    }
    
    /// The strategy to use in decoding dates. Defaults to `.deferredToDate`.
    open var dateDecodingStrategy: DateDecodingStrategy = .deferredToDate

    /// The strategy to use in decoding binary data. Defaults to `.base64`.
    open var dataDecodingStrategy: DataDecodingStrategy = .base64
    
    /// The strategy to use for decoding keys. Defaults to `.useDefaultKeys`.
    open var keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys
    
    /// Contextual user-provided information for use during decoding.
    open var userInfo: [CodingUserInfoKey: Any] = [:]
    
    /// Options set on the top-level encoder to pass down the decoding hierarchy.
    fileprivate struct _Options {
        let dateDecodingStrategy: DateDecodingStrategy
        let dataDecodingStrategy: DataDecodingStrategy
        let keyDecodingStrategy: KeyDecodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }
    
    /// The options set on the top-level decoder.
    fileprivate var options: _Options {
        return _Options(
            dateDecodingStrategy: dateDecodingStrategy,
            dataDecodingStrategy: dataDecodingStrategy,
            keyDecodingStrategy: keyDecodingStrategy,
            userInfo: userInfo
        )
    }
    
    // MARK: - Constructing a Dictionary Decoder
    
    /// Initializes `self` with default strategies.
    init() {}
    
    // MARK: - Decoding Values
    
    open func decode<T: Decodable>(_ type: T.Type, from dictionary: DictionaryValue?) throws -> T {
        try DictionaryDecoderImpl(from: dictionary, codingPath: [], options: options).unwrap(as: T.self)
    }
}

private struct DictionaryDecoderImpl {
    let codingPath: [CodingKey]
    let options: DictionaryDecoder._Options
    var userInfo: [CodingUserInfoKey : Any] { options.userInfo }
    
    let value: DictionaryValue?
    
    init(
        from value: DictionaryValue?,
        codingPath: [CodingKey],
        options: DictionaryDecoder._Options
    ) {
        self.codingPath = codingPath
        self.options = options
        self.value = value
    }
}

extension DictionaryDecoderImpl: Decoder {
    @usableFromInline func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        if let dictionary = value?.object {
            let container = KeyedContainer<Key>(
                impl: self,
                codingPath: codingPath,
                dictionary: dictionary
            )
            return KeyedDecodingContainer(container)
        }
        if let value {
            throw DecodingError.typeMismatch([String: DictionaryValue].self, .init(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([String: DictionaryValue].self) but found \(value.type) instead."
            ))
        } else {
            throw DecodingError.valueNotFound([String: DictionaryValue].self, .init(
                codingPath: codingPath,
                debugDescription: "Cannot get keyed decoding container -- found nil value instead"
            ))
        }
    }
    
    @usableFromInline func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        if let array = value?.array {
            return UnkeyedContainer(
                impl: self,
                codingPath: codingPath,
                array: array
            )
        }
        if let value {
            throw DecodingError.typeMismatch([DictionaryValue].self, .init(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([DictionaryValue].self) but found \(value.type) instead."
            ))
        } else {
            throw DecodingError.valueNotFound([DictionaryValue].self, .init(
                codingPath: codingPath,
                debugDescription: "Cannot get keyed decoding container -- found nil value instead"
            ))
        }
    }
    
    @usableFromInline func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleValueContainer(
            impl: self,
            codingPath: codingPath,
            value: value
        )
    }
    
    // MARK: Special case handling
    
    func unwrap<T: Decodable>(as type: T.Type) throws -> T {
        if type == Date.self {
            return try self.unwrapDate() as! T
        }
        if type == Data.self {
            return try self.unwrapData() as! T
        }
        if type == URL.self {
            return try self.unwrapURL() as! T
        }
        if type == Decimal.self {
            return try self.unwrapDecimal() as! T
        }
        return try T(from: self)
    }
    
    private func unwrapDate() throws -> Date {
        switch self.options.dateDecodingStrategy {
        case .deferredToDate:
            return try Date(from: self)
            
        case .secondsSince1970:
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, value: self.value)
            let double = try container.decode(Double.self)
            return Date(timeIntervalSince1970: double)
            
        case .millisecondsSince1970:
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, value: self.value)
            let double = try container.decode(Double.self)
            return Date(timeIntervalSince1970: double / 1000.0)
            
        case .iso8601:
            if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                let container = SingleValueContainer(impl: self, codingPath: self.codingPath, value: self.value)
                let string = try container.decode(String.self)
                guard let date = _iso8601Formatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: self.codingPath,
                        debugDescription: "Expected date string to be ISO8601-formatted."
                    ))
                }
                
                return date
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }
            
        case .formatted(let formatter):
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, value: self.value)
            let string = try container.decode(String.self)
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: self.codingPath,
                    debugDescription: "Date string does not match format expected by formatter."
                ))
            }
            return date
            
        case .custom(let closure):
            return try closure(self)
        }
    }
    
    private func unwrapData() throws -> Data {
        switch self.options.dataDecodingStrategy {
        case .deferredToData:
            return try Data(from: self)
            
        case .base64:
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, value: self.value)
            let string = try container.decode(String.self)
            
            guard let data = Data(base64Encoded: string) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: self.codingPath,
                    debugDescription: "Encountered Data is not valid Base64."
                ))
            }
            
            return data
            
        case .custom(let closure):
            return try closure(self)
        }
    }
    
    private func unwrapURL() throws -> URL {
        let container = SingleValueContainer(impl: self, codingPath: self.codingPath, value: self.value)
        let string = try container.decode(String.self)
        
        guard let url = URL(string: string) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: self.codingPath,
                debugDescription: "Invalid URL string."
            ))
        }
        return url
    }
    
    private func unwrapDecimal() throws -> Decimal {
        guard let decimal = self.value?.decimal else {
            throw DecodingError.typeMismatch(Decimal.self, .init(codingPath: self.codingPath, debugDescription: ""))
        }
        
        return decimal
    }
    
    private func unwrapFloatingPoint<T: BinaryFloatingPoint>(
        from value: DictionaryValue?,
        for additionalKey: CodingKey? = nil,
        as type: T.Type
    ) throws -> T {
        guard let double = value?.double else {
            throw self.createError(type: T.self, for: additionalKey, value: value)
        }
        
        if let floatingPoint = T(exactly: double) {
            return floatingPoint
        }
        
        var path = self.codingPath
        if let additionalKey = additionalKey {
            path.append(additionalKey)
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: path,
            debugDescription: "Dictionary number <\(double)> does not fit in \(T.self).")
        )
    }
    
    private func unwrapFixedWidthInteger<T: FixedWidthInteger>(
        from value: DictionaryValue?,
        for additionalKey: CodingKey? = nil,
        as type: T.Type
    ) throws -> T {
        guard let int = value?.int else {
            throw self.createError(type: T.self, for: additionalKey, value: value)
        }
        
        if let integer = T(exactly: int) {
            return integer
        }
        
        var path = self.codingPath
        if let additionalKey = additionalKey {
            path.append(additionalKey)
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: path,
            debugDescription: "Dictionary number <\(int)> does not fit in \(T.self).")
        )
    }
    
    private func createError(type: Any.Type, for additionalKey: CodingKey? = nil, value: DictionaryValue?) -> DecodingError {
        var path = codingPath
        if let additionalKey {
            path.append(additionalKey)
        }
        
        if let value {
            return DecodingError.typeMismatch(type, .init(
                codingPath: path,
                debugDescription: "Expected to decode \(type) but found \(value.type) instead."
            ))
        } else {
            return DecodingError.valueNotFound(type, .init(
                codingPath: path,
                debugDescription: "Expected to decode \(type) but found nil value instead."
            ))
        }
    }
}

extension DictionaryDecoderImpl {
    struct SingleValueContainer: SingleValueDecodingContainer {
        let impl: DictionaryDecoderImpl
        let codingPath: [CodingKey]
        let value: DictionaryValue?
        
        init(impl: DictionaryDecoderImpl, codingPath: [CodingKey], value: DictionaryValue?) {
            self.impl = impl
            self.codingPath = codingPath
            self.value = value
        }
        
        func decodeNil() -> Bool {
            value == nil
        }
        
        func decode(_ type: Bool.Type) throws -> Bool {
            guard let bool = value?.bool else {
                throw self.impl.createError(type: Bool.self, value: value)
            }
            
            return bool
        }
        
        func decode(_ type: String.Type) throws -> String {
            guard let string = value?.string else {
                throw self.impl.createError(type: String.self, value: value)
            }
            
            return string
        }
        
        func decode(_ type: Double.Type) throws -> Double {
            try decodeFloatingPoint()
        }
        
        func decode(_ type: Float.Type) throws -> Float {
            try decodeFloatingPoint()
        }
        
        func decode(_ type: Int.Type) throws -> Int {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: Int8.Type) throws -> Int8 {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: Int16.Type) throws -> Int16 {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: Int32.Type) throws -> Int32 {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: Int64.Type) throws -> Int64 {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: UInt.Type) throws -> UInt {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: UInt8.Type) throws -> UInt8 {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: UInt16.Type) throws -> UInt16 {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: UInt32.Type) throws -> UInt32 {
            try decodeFixedWidthInteger()
        }
        
        func decode(_ type: UInt64.Type) throws -> UInt64 {
            try decodeFixedWidthInteger()
        }
        
        func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
            try self.impl.unwrap(as: T.self)
        }
        
        private func decodeFixedWidthInteger<T: FixedWidthInteger>() throws -> T {
            try self.impl.unwrapFixedWidthInteger(from: self.value, as: T.self)
        }
        
        private func decodeFloatingPoint<T: BinaryFloatingPoint>() throws -> T {
            try self.impl.unwrapFloatingPoint(from: self.value, as: T.self)
        }
    }
}

extension DictionaryDecoderImpl {
    struct KeyedContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
        typealias Key = K
        
        let impl: DictionaryDecoderImpl
        let codingPath: [CodingKey]
        let dictionary: [String: DictionaryValue?]
        
        init(impl: DictionaryDecoderImpl, codingPath: [CodingKey], dictionary: [String: DictionaryValue?]) {
            self.impl = impl
            self.codingPath = codingPath
            
            switch impl.options.keyDecodingStrategy {
            case .useDefaultKeys:
                self.dictionary = dictionary
            case .convertFromSnakeCase:
                // Convert the snake case keys in the container to camel case.
                // If we hit a duplicate key after conversion, then we'll use the first one we saw.
                var converted = [String: DictionaryValue?]()
                converted.reserveCapacity(dictionary.count)
                dictionary.forEach { key, value in
                    converted[DictionaryDecoder.KeyDecodingStrategy._convertFromSnakeCase(key)] = value
                }
                self.dictionary = converted
            case let .custom(converter):
                var converted = [String: DictionaryValue?]()
                converted.reserveCapacity(dictionary.count)
                dictionary.forEach { key, value in
                    var pathForKey = codingPath
                    pathForKey.append(DictionaryCodingKey(stringValue: key))
                    converted[converter(pathForKey).stringValue] = value
                }
                self.dictionary = converted
            }
        }
        
        var allKeys: [K] {
            dictionary.keys.compactMap { K(stringValue: $0) }
        }
        
        func contains(_ key: K) -> Bool {
            if let _ = dictionary[key.stringValue] {
                return true
            }
            return false
        }
        
        func decodeNil(forKey key: K) throws -> Bool {
            let value = try getValue(forKey: key)
            return value == nil
        }
        
        func decode(_ type: Bool.Type, forKey key: K) throws -> Bool {
            let value = try getValue(forKey: key)
            
            guard let bool = value?.bool else {
                throw createError(type: type, forKey: key, value: value)
            }
            
            return bool
        }
        
        func decode(_ type: String.Type, forKey key: K) throws -> String {
            let value = try getValue(forKey: key)
            
            guard let string = value?.string else {
                throw createError(type: type, forKey: key, value: value)
            }
            
            return string
        }
        
        func decode(_ type: Double.Type, forKey key: K) throws -> Double {
            try decodeFloatingPoint(key: key)
        }
        
        func decode(_ type: Float.Type, forKey key: K) throws -> Float {
            try decodeFloatingPoint(key: key)
        }
        
        func decode(_ type: Int.Type, forKey key: K) throws -> Int {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: Int8.Type, forKey key: K) throws -> Int8 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: Int16.Type, forKey key: K) throws -> Int16 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: Int32.Type, forKey key: K) throws -> Int32 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: Int64.Type, forKey key: K) throws -> Int64 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: UInt.Type, forKey key: K) throws -> UInt {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: UInt8.Type, forKey key: K) throws -> UInt8 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 {
            try decodeFixedWidthInteger(key: key)
        }
        
        func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T: Decodable {
            let newDecoder = try decoderForKey(key)
            return try newDecoder.unwrap(as: T.self)
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
            try decoderForKey(key).container(keyedBy: type)
        }
        
        func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
            try decoderForKey(key).unkeyedContainer()
        }
        
        func superDecoder() throws -> Decoder {
            decoderForKeyNoThrow(DictionaryCodingKey.super)
        }
        
        func superDecoder(forKey key: K) throws -> Decoder {
            decoderForKeyNoThrow(key)
        }
        
        private func decoderForKey<LocalKey: CodingKey>(_ key: LocalKey) throws -> DictionaryDecoderImpl {
            let value = try getValue(forKey: key)
            var newPath = codingPath
            newPath.append(key)
            
            return DictionaryDecoderImpl(
                from: value,
                codingPath: newPath,
                options: self.impl.options
            )
        }
        
        private func decoderForKeyNoThrow<LocalKey: CodingKey>(_ key: LocalKey) -> DictionaryDecoderImpl {
            let value: DictionaryValue?
            do {
                value = try getValue(forKey: key)
            } catch {
                // if there no value for this key then return a null value
                value = nil
            }
            var newPath = codingPath
            newPath.append(key)
            
            return DictionaryDecoderImpl(
                from: value,
                codingPath: newPath,
                options: self.impl.options
            )
        }
        
        private func getValue<LocalKey: CodingKey>(forKey key: LocalKey) throws -> DictionaryValue? {
            guard let value = dictionary[key.stringValue] else {
                throw DecodingError.keyNotFound(key, .init(
                    codingPath: codingPath,
                    debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\")."
                ))
            }
            
            return value
        }
        
        private func createError(type: Any.Type, forKey key: K, value: DictionaryValue?) -> DecodingError {
            let codingPath = self.codingPath + [key]
            guard let value else {
                return DecodingError.valueNotFound(type, .init(
                    codingPath: codingPath,
                    debugDescription: "Expected to decode \(type) but found nil value instead."
                ))
            }
            return DecodingError.typeMismatch(type, .init(
                codingPath: codingPath,
                debugDescription: "Expected to decode \(type) but found \(value.type) instead."
            ))
        }
        
        private func decodeFixedWidthInteger<T: FixedWidthInteger>(key: Key) throws -> T {
            let value = try getValue(forKey: key)
            return try self.impl.unwrapFixedWidthInteger(from: value, for: key, as: T.self)
        }
        
        private func decodeFloatingPoint<T: BinaryFloatingPoint>(key: Key) throws -> T {
            let value = try getValue(forKey: key)
            return try self.impl.unwrapFloatingPoint(from: value, for: key, as: T.self)
        }
    }
}

extension DictionaryDecoderImpl {
    struct UnkeyedContainer: UnkeyedDecodingContainer {
        let impl: DictionaryDecoderImpl
        let codingPath: [CodingKey]
        let array: [DictionaryValue?]
        
        var count: Int? { array.count }
        var isAtEnd: Bool { currentIndex >= (count ?? 0) }
        var currentIndex: Int = 0
        
        init(impl: DictionaryDecoderImpl, codingPath: [CodingKey], array: [DictionaryValue?]) {
            self.impl = impl
            self.codingPath = codingPath
            self.array = array
        }
        
        mutating func decodeNil() throws -> Bool {
            if try getNextValue(ofType: Never.self) == nil {
                currentIndex += 1
                return true
            }
            
            return false
        }
        
        mutating func decode(_ type: Bool.Type) throws -> Bool {
            let value = try getNextValue(ofType: type)
            guard let bool = value?.bool else {
                throw self.impl.createError(type: type, for: DictionaryCodingKey(index: currentIndex), value: value)
            }
            
            return bool
        }
        
        mutating func decode(_ type: String.Type) throws -> String {
            let value = try getNextValue(ofType: type)
            guard let string = value?.string else {
                throw self.impl.createError(type: type, for: DictionaryCodingKey(index: currentIndex), value: value)
            }
            
            return string
        }
        
        mutating func decode(_ type: Double.Type) throws -> Double {
            try decodeFloatingPoint()
        }
        
        mutating func decode(_ type: Float.Type) throws -> Float {
            try decodeFloatingPoint()
        }
        
        mutating func decode(_ type: Int.Type) throws -> Int {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: Int8.Type) throws -> Int8 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: Int16.Type) throws -> Int16 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: Int32.Type) throws -> Int32 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: Int64.Type) throws -> Int64 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: UInt.Type) throws -> UInt {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
            try decodeFixedWidthInteger()
        }
        
        mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
            let newDecoder = try decoderForNextElement(ofType: T.self)
            let result = try newDecoder.unwrap(as: T.self)
            self.currentIndex += 1
            return result
        }
        
        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
            let decoder = try decoderForNextElement(ofType: KeyedDecodingContainer<NestedKey>.self)
            let container = try decoder.container(keyedBy: type)
            
            currentIndex += 1
            return container
        }
        
        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            let decoder = try decoderForNextElement(ofType: UnkeyedDecodingContainer.self)
            let container = try decoder.unkeyedContainer()
            
            currentIndex += 1
            return container
        }
        
        mutating func superDecoder() throws -> Decoder {
            let decoder = try decoderForNextElement(ofType: Decoder.self)
            currentIndex += 1
            return decoder
        }
        
        private func decoderForNextElement<T>(ofType: T.Type) throws -> DictionaryDecoderImpl {
            let value = try getNextValue(ofType: T.self)
            let newPath = codingPath + [DictionaryCodingKey(index: currentIndex)]
            
            return DictionaryDecoderImpl(
                from: value,
                codingPath: newPath,
                options: impl.options
            )
        }
        
        private func getNextValue<T>(ofType: T.Type) throws -> DictionaryValue? {
            guard !isAtEnd else {
                var message = "Unkeyed container is at end."
                if T.self == UnkeyedContainer.self {
                    message = "Cannot get nested unkeyed container -- unkeyed container is at end."
                }
                if T.self == Decoder.self {
                    message = "Cannot get superDecoder() -- unkeyed container is at end."
                }
                
                var path = codingPath
                path.append(DictionaryCodingKey(index: currentIndex))
                
                throw DecodingError.valueNotFound(
                    T.self,
                    .init(
                        codingPath: path,
                        debugDescription: message,
                        underlyingError: nil
                    )
                )
            }
            return array[currentIndex]
        }
        
        private mutating func decodeFixedWidthInteger<T: FixedWidthInteger>() throws -> T {
            let value = try getNextValue(ofType: T.self)
            let key = DictionaryCodingKey(index: self.currentIndex)
            let result = try self.impl.unwrapFixedWidthInteger(from: value, for: key, as: T.self)
            self.currentIndex += 1
            return result
        }
        
        private mutating func decodeFloatingPoint<T: BinaryFloatingPoint>() throws -> T {
            let value = try getNextValue(ofType: T.self)
            let key = DictionaryCodingKey(index: self.currentIndex)
            let result = try self.impl.unwrapFloatingPoint(from: value, for: key, as: T.self)
            self.currentIndex += 1
            return result
        }
    }
}

