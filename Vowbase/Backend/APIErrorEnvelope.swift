struct APIErrorEnvelope: Decodable, Sendable, Equatable {
    let error: Detail

    struct Detail: Decodable, Sendable, Equatable {
        let code: String
        let message: String
        let requestID: String?

        private enum CodingKeys: String, CodingKey {
            case code
            case message
            case requestID = "requestId"
        }
    }
}
