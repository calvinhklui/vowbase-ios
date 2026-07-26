enum BackendError: Error, Equatable, Sendable {
    case authenticationRequired(message: String?, requestID: String?)
    case forbidden(message: String, requestID: String?)
    case validation(message: String, requestID: String?)
    case conflict(message: String, requestID: String?)
    case rateLimited(message: String, requestID: String?)
    case temporarilyUnavailable(message: String, requestID: String?)
    case networkUnavailable
    case invalidResponse
    case cancelled
    case unknown(message: String, requestID: String?)

    init(detail: APIErrorEnvelope.Detail) {
        switch detail.code {
        case "authentication_required":
            self = .authenticationRequired(
                message: detail.message,
                requestID: detail.requestID
            )
        case "forbidden", "wedding_forbidden":
            self = .forbidden(message: detail.message, requestID: detail.requestID)
        case "validation_failed":
            self = .validation(message: detail.message, requestID: detail.requestID)
        case "method_not_allowed":
            self = .unknown(message: detail.message, requestID: detail.requestID)
        case "conflict":
            self = .conflict(message: detail.message, requestID: detail.requestID)
        case "rate_limited":
            self = .rateLimited(message: detail.message, requestID: detail.requestID)
        case "temporarily_unavailable", "provider_failed", "internal_failure":
            self = .temporarilyUnavailable(
                message: detail.message,
                requestID: detail.requestID
            )
        default:
            self = .unknown(message: detail.message, requestID: detail.requestID)
        }
    }
}

extension APIErrorEnvelope {
    var backendError: BackendError {
        BackendError(detail: error)
    }
}
