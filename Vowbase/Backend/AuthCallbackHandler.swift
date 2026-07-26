import Foundation

actor AuthCallbackHandler {
    enum Outcome: Equatable, Sendable {
        case handled
        case rejected
        case failed(BackendError)
    }

    private static let failureMessage = "Authentication callback failed."

    private let auth: any AuthServicing
    private var tail: Task<Outcome, Never>?
    private var latestOutcomeSequence = 0

    private(set) var latestOutcome: Outcome?
    private(set) var enqueuedCallbackCount = 0

    init(auth: any AuthServicing) {
        self.auth = auth
    }

    func enqueue(_ url: URL) async -> Outcome {
        enqueuedCallbackCount += 1
        let sequence = enqueuedCallbackCount
        let previous = tail
        let auth = self.auth
        let operation = Task {
            if let previous {
                _ = await previous.value
            }
            return await Self.process(url, auth: auth)
        }
        tail = operation

        let outcome = await operation.value
        if sequence > latestOutcomeSequence {
            latestOutcomeSequence = sequence
            latestOutcome = outcome
        }
        return outcome
    }

    private static func process(
        _ url: URL,
        auth: any AuthServicing
    ) async -> Outcome {
        guard isAuthCallback(url) else {
            return .rejected
        }

        do {
            try await auth.handle(url: url)
            return .handled
        } catch {
            return .failed(normalized(error))
        }
    }

    private static func isAuthCallback(_ url: URL) -> Bool {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return false
        }

        return components.scheme?.lowercased() == "vowbase"
            && components.host?.lowercased() == "auth"
            && components.percentEncodedPath == "/callback"
            && components.user == nil
            && components.password == nil
            && components.port == nil
            && components.fragment == nil
    }

    private static func normalized(_ error: any Error) -> BackendError {
        if let backendError = error as? BackendError {
            return backendError
        }
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .networkUnavailable
        }
        return .temporarilyUnavailable(message: failureMessage, requestID: nil)
    }
}
