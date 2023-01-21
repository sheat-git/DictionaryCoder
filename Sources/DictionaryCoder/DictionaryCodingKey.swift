//
//  DictionaryCodingKey.swift
//  
//
//  Created by sheat on 2023/01/16.
//

import Foundation

struct DictionaryCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String, intValue: Int? = nil) {
        self.stringValue = stringValue
        self.intValue = intValue
    }
    
    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }
    
    init(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
    
    init(index: Int) {
        stringValue = "Index \(index)"
        intValue = index
    }
    
    static let `super` = DictionaryCodingKey(stringValue: "super")
}
