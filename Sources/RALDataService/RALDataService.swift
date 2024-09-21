
import Foundation

//MARK: - General purpose Data NWModel protocols
public protocol NWModel {}
extension Array: NWModel where Element: NWModel {}

//MARK: - DataService

public protocol DataService {
    typealias Errors = RALDataService.Errors
    
    //generic requests
    func performDataRequest<T: NWModel, E: Endpoint>(_ endpoint: E, decoder: @escaping ((E.ResponseData)->T?), completion: ResultCompletion<T, Errors>?) -> NetworkTask
    func performDataRequest<T: NWModel, E: Endpoint>(_ endpoint: E, decoder: @escaping ((E.ResponseData)->T?), completion: ResultCompletion<T, Errors>?, completeOn queue: DispatchQueue) -> NetworkTask
    
    // async/await
    
    // #takeaway we can expose modern APIs that USE the old implementation, to use the modern API at consumer side
    
    // #TODO: when upgrading to Swift 6 (Xcode 16) consider using typed throws for typed error results
    func performDataRequest<T: NWModel, E: Endpoint>(_ endpoint: E, decoder: @escaping ((E.ResponseData)->T?)) async throws -> T
}

//MARK: - RALDataService

open class RALDataService: DataService {
    public enum Errors: Error, ErrorInitializable {
        case managerDeallocated
        case parsingFailed
        case noContentResponse
        case connection
        case serverError(String)
        case unknown(Error)
        
        public init(error: Error) {
            self = .unknown(error)
        }
    }
    
    let networkRequester: NetworkRequester

    public init(networkRequester: NetworkRequester) {
        self.networkRequester = networkRequester
    }

    public func performDataRequest<T, E>(_ endpoint: E, decoder: @escaping ((E.ResponseData) -> T?), completion: ResultCompletion<T, Errors>?) -> NetworkTask where T : NWModel, E : Endpoint {
        self.performDataRequest(endpoint, decoder: decoder, completion: completion, completeOn: .main)
    }

    public func performDataRequest<T: NWModel, E: Endpoint>(_ endpoint: E, decoder: @escaping ((E.ResponseData)->T?), completion: ResultCompletion<T, Errors>?, completeOn queue: DispatchQueue) -> NetworkTask {
        
        return self.networkRequester.execute(endpoint: endpoint) { (result: Result<E.RawResponseData, NetworkRequester.Errors>) in
            
            let completeOnQueue = { (result: Result<T, Errors>) in
                queue.async {
                    completion?(result)
                }
            }
            
            switch result {
            case .success(let data):
                ///we first need to traverse the response to reach inside the raw response, and find the part we can actually decode
                guard let traversed = endpoint.traverse(rawResponse: data),
                      let decodedData = decoder(traversed) else {
                    completeOnQueue(.failure(.parsingFailed))
                    return
                }
                completeOnQueue(.success(decodedData))
                
            case .failure(let error):
                completeOnQueue(.failure(Errors(error: error)))
            }
        }
    }
    
    // Async/await

    public func performDataRequest<T: NWModel, E: Endpoint>(_ endpoint: E, decoder: @escaping ((E.ResponseData)->T?)) async throws -> T {
        
        // #takeaway when bridging block-based async to Swift Concurrency, we can use Continuations to expose a modern async API but use internnally the block_based implementation. we just need to resume the continuation when done (and ALWAYS should be RESUMED at some ponint?)
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: Errors.managerDeallocated)
                return
            }
            
            let _ = self.performDataRequest(endpoint, decoder: decoder) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }
}
