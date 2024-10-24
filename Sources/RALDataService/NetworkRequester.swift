
import Foundation
import RALLogger

//MARK: Types
public struct EmptyType {
    init() {}
}
extension EmptyType: NWModel {}

public typealias ResultCompletion<T, E: Error> = ((Swift.Result<T, E>) -> Void)
public typealias SSLCertificates = [Host: [Certificate]]
public typealias Host = String
public typealias Certificate = String

//MARK: NetworkData

///Protocol for defining what types are allowed to be returned from a network request. for now only supporting EmptyType and JSON. if a new type is added, we need to update the `RALNetworkRequester.execute<T>` method below
public protocol NetworkData {}
extension JSON: NetworkData {}
extension Array: NetworkData where Element == JSON {}
extension EmptyType: NetworkData {}

//MARK: - NetworkTask

public protocol NetworkTask {
    var identifier: String { get }
    func cancel()
}

public struct RALNetworkTask: NetworkTask {
    
    let sessionTask: URLSessionTask
    public let identifier: String
    
    init(sessionTask: URLSessionTask, identifier: String = UUID().uuidString) {
        self.sessionTask = sessionTask
        self.identifier = identifier
    }
    
    public func cancel() {
        self.sessionTask.cancel()
    }
}

//MARK: - NetworkRequester

public enum NetworkRequesterError: Error {
    case HTTPResponseNotFound
    case badHTTPResponseCode(Data?)
    case taskCancelled
    case noContentResponse
    case failedToDecodeResponse
    case unsupportedResponseDataFormat
    case missingResponseData
    case connection
    case unknown(Error)
}

public protocol NetworkRequester {
    typealias Errors = NetworkRequesterError
    @discardableResult
    func execute<T: NetworkData, E: Endpoint>(endpoint: E, completion: @escaping ResultCompletion<T, Errors>) -> NetworkTask
}


public struct NetworkConfiguration {
    let baseURL: URL
    let sessionConfiguration: URLSessionConfiguration
    let sslCertificates: SSLCertificates
    
    public init(baseURL: URL, sessionConfiguration: URLSessionConfiguration, sslCertificates: SSLCertificates) {
        self.baseURL = baseURL
        self.sessionConfiguration = sessionConfiguration
        self.sslCertificates = sslCertificates
    }
}

public class RALNetworkRequester: NSObject, NetworkRequester {
    
    private lazy var session: URLSession = {
        URLSession(configuration: self.sessionConfiguration, delegate: self, delegateQueue: nil)
    }()
    private let sessionConfiguration: URLSessionConfiguration
    private let sslCertificates: SSLCertificates
    private let certificatePinner = CertificatePinner()
    private let baseURL: URL
    
    public init(networkConfiguration: NetworkConfiguration) {
        self.baseURL = networkConfiguration.baseURL
        self.sessionConfiguration = networkConfiguration.sessionConfiguration
        self.sslCertificates = networkConfiguration.sslCertificates
        super.init()
    }
    
    @discardableResult
    public func execute<T, E>(endpoint: E, completion: @escaping (Result<T, Errors>) -> Void) -> NetworkTask where T : NetworkData, E : Endpoint {

        let session = self.session
        let urlRequest = endpoint.urlRequest(baseURL: self.baseURL)

        Logger.shared.log("urlRequest: \(urlRequest.curlString)")

        let task = session.dataTask(with: urlRequest) { (data, response, error) in
            
            //Error scenario
            if let error = error {
                completion(.failure(.unknown(error)))
                return
            }
            
            //Bad HTTP header scenario
            if let response = response as? HTTPURLResponse {
                let responseCode = response.statusCode
                switch responseCode {
                case 200..<300: break
                default:
                    completion(.failure(.badHTTPResponseCode(data)))
                    return
                }
            }
            
            //response data validation
            guard let data = data else {
                completion(.failure(.missingResponseData))
                return
            }
            
            if T.self == JSON.self || T.self == [JSON].self {
                //JSON and [JSON] support
                guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? T else {
                    completion(.failure(.failedToDecodeResponse))
                    return
                }
                completion(.success(json))
                return
                
            } else if T.self == EmptyType.self {
                //EmptyType support
                completion(.success(EmptyType() as! T))
                return

            } else {
                //Unsupported
                Logger.shared.log("Only JSON and EmptyType response data formats are supported. did we add a new supported type?")
                completion(.failure(.unsupportedResponseDataFormat))
                return
            }
            
        }
        
        task.resume()
        return RALNetworkTask(sessionTask: task)
    }
}

//MARK: - URLSessionDelegate

extension RALNetworkRequester: URLSessionDelegate {
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        self.certificatePinner.performPinning(for: challenge, using: self.sslCertificates, completionHandler: completionHandler)
    }
}

private extension NetworkRequester.Errors {
    init(urlError error: URLError) {
        switch error.code {
        case .cancelled: self = .taskCancelled
        case .notConnectedToInternet: self = .connection
        case .networkConnectionLost: self = .connection
        case .timedOut: self = .connection
        default: self = .unknown(error)
        }
    }
}
