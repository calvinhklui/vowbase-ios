import Foundation
import Testing
@testable import Vowbase

@Suite("Backend errors")
struct BackendErrorTests {
    @Test("decodes and maps the wedding forbidden fixture")
    func decodesAndMapsWeddingForbiddenFixture() throws {
        let bundle = Bundle(for: BackendErrorTestsBundleToken.self)
        #expect(bundle.bundleURL.pathExtension == "xctest")

        let fixtureURL = try #require(
            bundle.url(
                forResource: "error-wedding-forbidden",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "error-wedding-forbidden",
                withExtension: "json"
            )
        )
        let envelope = try JSONDecoder().decode(
            APIErrorEnvelope.self,
            from: Data(contentsOf: fixtureURL)
        )

        requireSendable(envelope)
        #expect(
            envelope == APIErrorEnvelope(
                error: .init(
                    code: "wedding_forbidden",
                    message: "Forbidden.",
                    requestID: "req-1"
                )
            )
        )
        #expect(
            envelope.backendError
                == .forbidden(message: "Forbidden.", requestID: "req-1")
        )
    }

    @Test("maps every current server API error code")
    func mapsEveryCurrentServerAPIErrorCode() {
        let message = "Safe server message."
        let requestID = "req-current"
        let cases: [(String, BackendError)] = [
            (
                "authentication_required",
                .authenticationRequired(message: message, requestID: requestID)
            ),
            ("forbidden", .forbidden(message: message, requestID: requestID)),
            ("wedding_forbidden", .forbidden(message: message, requestID: requestID)),
            ("validation_failed", .validation(message: message, requestID: requestID)),
            ("method_not_allowed", .unknown(message: message, requestID: requestID)),
            ("conflict", .conflict(message: message, requestID: requestID)),
            ("rate_limited", .rateLimited(message: message, requestID: requestID)),
            (
                "temporarily_unavailable",
                .temporarilyUnavailable(message: message, requestID: requestID)
            ),
            (
                "provider_failed",
                .temporarilyUnavailable(message: message, requestID: requestID)
            ),
            (
                "internal_failure",
                .temporarilyUnavailable(message: message, requestID: requestID)
            ),
        ]

        for (code, expected) in cases {
            let detail = APIErrorEnvelope.Detail(
                code: code,
                message: message,
                requestID: requestID
            )
            #expect(BackendError(detail: detail) == expected)
        }
    }

    @Test("authentication errors support absent local and partial server diagnostics")
    func authenticationErrorsSupportOptionalDiagnostics() {
        let localError = BackendError.authenticationRequired(
            message: nil,
            requestID: nil
        )
        let serverError = BackendError(
            detail: .init(
                code: "authentication_required",
                message: "Authentication required.",
                requestID: nil
            )
        )

        #expect(
            localError == .authenticationRequired(message: nil, requestID: nil)
        )
        #expect(
            serverError == .authenticationRequired(
                message: "Authentication required.",
                requestID: nil
            )
        )
    }

    @Test("decodes missing and null request IDs as nil")
    func decodesMissingAndNullRequestIDs() throws {
        let missing = try decode(#"{"error":{"code":"conflict","message":"Conflict."}}"#)
        let null = try decode(
            #"{"error":{"code":"conflict","message":"Conflict.","requestId":null}}"#
        )

        #expect(missing.error.requestID == nil)
        #expect(null.error.requestID == nil)
        #expect(missing.backendError == .conflict(message: "Conflict.", requestID: nil))
        #expect(null.backendError == .conflict(message: "Conflict.", requestID: nil))
    }

    @Test("maps unknown and blank codes without changing safe detail values")
    func mapsUnknownAndBlankCodes() {
        let cases = ["future_error", "", "  \n\t"]

        for code in cases {
            let detail = APIErrorEnvelope.Detail(
                code: code,
                message: "Preserve me.",
                requestID: "req-unknown"
            )
            #expect(
                BackendError(detail: detail)
                    == .unknown(message: "Preserve me.", requestID: "req-unknown")
            )
        }
    }

    @Test("rejects malformed error envelopes")
    func rejectsMalformedErrorEnvelopes() {
        let malformedEnvelopes = [
            #"{}"#,
            #"{"error":{"message":"Missing code."}}"#,
            #"{"error":{"code":"forbidden"}}"#,
            #"{"error":{"code":1,"message":"Wrong code type."}}"#,
        ]

        for json in malformedEnvelopes {
            #expect(throws: DecodingError.self) {
                try decode(json)
            }
        }
    }

    @Test("backend errors have equatable sendable value semantics")
    func backendErrorsHaveEquatableSendableValueSemantics() {
        let errors: [BackendError] = [
            .authenticationRequired(message: nil, requestID: nil),
            .forbidden(message: "Forbidden.", requestID: "req-1"),
            .validation(message: "Invalid.", requestID: nil),
            .conflict(message: "Conflict.", requestID: "req-2"),
            .rateLimited(message: "Slow down.", requestID: nil),
            .temporarilyUnavailable(message: "Try later.", requestID: "req-3"),
            .networkUnavailable,
            .invalidResponse,
            .cancelled,
            .unknown(message: "Unknown.", requestID: nil),
        ]
        let copy = errors

        requireSendable(errors)
        #expect(copy == errors)
        #expect(copy[1] != copy[2])
    }

    @Test("preserves server messages for user-facing error presentation")
    func exposesServerMessages() {
        #expect(
            BackendError.validation(message: "Choose a venue status.", requestID: nil).message
                == "Choose a venue status."
        )
        #expect(BackendError.authenticationRequired(message: nil, requestID: nil).message == nil)
        #expect(BackendError.networkUnavailable.message == nil)
    }

    private func decode(_ json: String) throws -> APIErrorEnvelope {
        try JSONDecoder().decode(APIErrorEnvelope.self, from: Data(json.utf8))
    }

    private func requireSendable<T: Sendable>(_: T) {}
}

private final class BackendErrorTestsBundleToken {}
