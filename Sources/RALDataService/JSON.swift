
import Foundation

public typealias JSON = [String: Any]

/// Convenience subscripts for getting different types from a JSON
public extension JSON {
    
    //MARK: - JSON
    subscript(jsonFor key: String) -> JSON? {
        return self[key] as? JSON
    }
    
    subscript(jsonValueFor key: String) -> JSON {
        get { return self[jsonFor: key] ?? [:] }
    }
    
    subscript(arrayFor key: String) -> [JSON]? {
        return self[key] as? [JSON]
    }
    
    subscript(arrayValueFor key: String) -> [JSON] {
        return self[key] as? [JSON] ?? []
    }
    
    //MARK: - Int
    subscript(intFor key: String) -> Int? {
        return self[key] as? Int
    }
    
    subscript(intValueFor key: String) -> Int {
        return self[intFor: key] ?? 0
    }
    
    //MARK: - Double

    subscript(doubleFor key: String) -> Double? {
        return self[key] as? Double
    }
    
    subscript(doubleValueFor key: String) -> Double {
        return self[doubleFor: key] ?? 0.0
    }
    
    //MARK: - String
    subscript(stringFor key: String) -> String? {
        return self[key] as? String
    }
    
    subscript(stringValueFor key: String) -> String {
        return self[stringFor: key] ?? ""
    }
    
    //MARK: - URL
    
    subscript(urlFor key: String) -> URL? {
        return self[stringFor: key].flatMap({ URL(string: $0) })
    }

    //MARK: - Generic
    
    subscript<T>(objectFor key: String) -> T? {
        return self[key] as? T
    }
}
