import Foundation

struct APIRequest<Response: Decodable & Sendable>: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    let method: Method
    let path: String
    let body: Data?
    let headers: [String: String]

    init(
        method: Method,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.body = body
        self.headers = headers
    }
}
