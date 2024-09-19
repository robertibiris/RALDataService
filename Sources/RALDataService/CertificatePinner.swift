
import Foundation

struct CertificatePinner {
    
    enum PinningOutcome {
        case successfulPin
        case defaultHandling
        case operationCancelled
    }
    
    enum Errors: Error {
        case missingCertificatesForHost
        case serverTrustNotFound
        case invalidServerTrust
        case failedToExtractServerCertificate
        case noMatchingCertificatesFound
    }
    
    @discardableResult
    func performPinning(for challenge: URLAuthenticationChallenge, using certificates: SSLCertificates, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) -> PinningOutcome {
        
        let host = challenge.protectionSpace.host
        let pinningResult = self.validatePinning(challenge: challenge, using: certificates)
        
        switch pinningResult {
        case .success(let serverTrust):
            //complete pinning
            let credential = URLCredential(trust: serverTrust)
            challenge.sender?.use(credential, for: challenge)
            completionHandler(.useCredential, credential)
            
            return .successfulPin
            
        case .failure(let error):
            switch error {
            case .missingCertificatesForHost:
                //go ahead with default handling
                challenge.sender?.performDefaultHandling?(for: challenge)
                completionHandler(.performDefaultHandling, nil)
                
                return .defaultHandling
                
            case .serverTrustNotFound, .invalidServerTrust, .failedToExtractServerCertificate, .noMatchingCertificatesFound:
                //cancel request
                print("ERROR!!!: CertificatePinner Challenge cancelled for \(host)")
//                Logger.shared.log("CertificatePinner Challenge cancelled for \(host)", level: .error)
                challenge.sender?.cancel(challenge)
                completionHandler(.cancelAuthenticationChallenge, nil)
                
                return .operationCancelled
            }
        }
    }
        
    func validatePinning(challenge: URLAuthenticationChallenge, using certificates: SSLCertificates) -> Swift.Result<SecTrust, Errors> {
        
        let host = challenge.protectionSpace.host
        let hostCertificatesOpt = certificates.first(where: { (key, _) in
            return key.contains(host)
        })?.value
        
        //if we have no certificates to compare, we fallback to default behavior
        guard let hostCertificates = hostCertificatesOpt,
            !hostCertificates.isEmpty else {
                return .failure(.missingCertificatesForHost)
        }
        
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            return .failure(.serverTrustNotFound)
        }
        
        //check with the system to determine if this `serverTrust` is reliable (will fail for self-signed certificates)
        var resultType: SecTrustResultType = .unspecified
        guard SecTrustEvaluate(serverTrust, &resultType) == noErr else {
            return .failure(.invalidServerTrust)
        }
        
        guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            return .failure(.failedToExtractServerCertificate)
        }
        
        //Actual pinning
        let remoteCertificateData = SecCertificateCopyData(certificate) as Data
        if let _ = hostCertificates.lazy.compactMap({ Data(base64Encoded: $0) }).first(where: {
            print("CERTIFICATE:\n\($0.base64EncodedString())")
            print("\nremoteCertificateData:\n\(remoteCertificateData.base64EncodedString())")
            return $0 == remoteCertificateData
        }) {
            return .success(serverTrust)
        } else {
            return.failure(.noMatchingCertificatesFound)
        }
        
    }
}

