
import Foundation

typealias NWPath = String
typealias HTTPHeaders = [String: String]
typealias URLParameters = [String: String]


enum HTTPMethod {
    case get
    case post
    case put
    case patch
    case delete
}

enum HTTPBody {
    case json(JSON)
    case data(Data, contentType: String)

    var dataValue: Data? {
        switch self {
        case .json(let json):
            return try? JSONSerialization.data(withJSONObject: json, options: [])
        case .data(let data, _):
            return data
        }
    }
    
    var contentType: String {
        switch self {
        case .json: return "application/json"
        case .data(_, let contentType): return contentType
        }
    }
}

enum EndpointAuthentication {
    case none, basic, authenticated
}

protocol Endpoint {
    ///The non-traversed response type
    associatedtype RawResponseData: NetworkData
    ///The traversed response type
    associatedtype ResponseData: NetworkData

    var path: NWPath { get }
    var method: HTTPMethod { get }
    var parameters: URLParameters? { get }
    var body: HTTPBody? { get }
    var headers: HTTPHeaders? { get }
    /// Traversing the response (for instance into a nested inner JSON) to reach the actual desired response output type. For instance, we may want to reach `json["result"][0]["nested"]`
    /// - Parameter rawResponse: the raw response to be traversed
    func traverse(rawResponse: RawResponseData) -> ResponseData?
}

extension Endpoint {
    func urlRequest(baseURL: URL) -> URLRequest {
        
        let fullURL: URL
        
        //path & query
        let urlWithPath = baseURL.appendingPathComponent(self.path)
        
        var components = URLComponents(url: urlWithPath, resolvingAgainstBaseURL: false)!
        components.queryItems = self.parameters?.asQueryItems()
        
        ///Due to an apparent bug on URLComponents, we need to manually percent-encode the "+" sign when appearing inside the query items
        components.percentEncodedQueryItems = components.percentEncodedQueryItems?.map({ URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "+").inverted)) })
        
        fullURL = components.url!
//        print("percent-encoded: \(components.percentEncodedQuery ?? "")")
        //method
        var result = URLRequest(url: fullURL)
        result.httpMethod = self.method.ral_systemValue
    
        //Body
        if let body = self.body {
            result.httpBody = body.dataValue
            result.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        }
        
        //Headers
        //endpoint-specific headers
        self.headers?.forEach { result.setValue($1, forHTTPHeaderField: $0) }
        
        return result
    }
}

///Convenience for a default impleemntation when `RawResponseData == ResponseData`, we just return the raw value directly. This is only to avoid biolerplate of endpoints that don't really need traversing
extension Endpoint where RawResponseData == ResponseData {
    func traverse(rawResponse: RawResponseData) -> ResponseData? {
        return rawResponse
    }
}

protocol GetEndpoint: Endpoint {}
extension GetEndpoint {
    var method: HTTPMethod { return .get }
    var body: HTTPBody? { return nil }
}

protocol PostEndpoint: Endpoint {}
extension PostEndpoint {
    var method: HTTPMethod { return .post }
}

protocol PutEndpoint: Endpoint {}
extension PutEndpoint {
    var method: HTTPMethod { return .put }
}

protocol PatchEndpoint: Endpoint {}
extension PatchEndpoint {
    var method: HTTPMethod { return .patch }
}

protocol DeleteEndpoint: Endpoint {}
extension DeleteEndpoint {
    var method: HTTPMethod { return .delete }
}

//MARK: - Utils

extension URLParameters where Key == String, Value == String {
    func asQueryItems() -> [URLQueryItem]? {
        return self.map { URLQueryItem(name: $0, value: $1) }
    }
}

extension HTTPMethod {
    var ral_systemValue: String {
        switch self {
        case .get: return "GET"
        case .post: return "POST"
        case .put: return "PUT"
        case .patch: return "PATCH"
        case .delete: return "DELETE"
        }
    }
}
