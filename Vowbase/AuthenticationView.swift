import AuthenticationServices
import CryptoKit
import Observation
import Supabase
import SwiftUI

@MainActor
@Observable
final class AuthenticationCoordinator {
    enum Operation: Equatable {
        case google
        case apple
        case signOut
    }

    private let auth: any AuthServicing
    private var stateTask: Task<Void, Never>?
    private var appleNonce: String?

    var state: AuthenticationState = .loading
    var operation: Operation?
    var message: String?
#if DEBUG
    var isTestingWorkspaceActive = false
#endif

    init(auth: any AuthServicing) {
        self.auth = auth
        stateTask = Task { [weak self, auth] in
            for await state in auth.states {
                guard !Task.isCancelled else { return }
                self?.apply(state)
            }
        }
    }

    var isSigningIn: Bool {
        operation == .google || operation == .apple
    }

    func retry() {
        message = nil
        state = .loading
        Task { [weak self, auth] in
            do {
                try await auth.refreshSession()
            } catch {
                self?.record(error)
            }
        }
    }

    func signInWithGoogle() {
        guard operation == nil else { return }
        operation = .google
        message = nil

        Task { [weak self, auth] in
            do {
                try await auth.signInWithGoogle()
            } catch {
                self?.record(error)
            }
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AuthenticationNonce.make()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AuthenticationNonce.sha256(nonce)
        message = nil
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            record(error)

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken,
                  let token = String(data: identityToken, encoding: .utf8),
                  let nonce = appleNonce else {
                message = "Apple sign-in could not be completed. Please try again."
                return
            }

            operation = .apple
            Task { [weak self, auth] in
                do {
                    try await auth.signInWithIDToken(
                        provider: .apple,
                        token: token,
                        nonce: nonce
                    )
                } catch {
                    self?.record(error)
                }
            }
        }
    }

    func signOut() {
        guard operation == nil else { return }
        operation = .signOut
        message = nil

        Task { [weak self, auth] in
            do {
                try await auth.signOut()
            } catch {
                self?.record(error)
            }
        }
    }

#if DEBUG
    func enterTestingWorkspace() {
        isTestingWorkspaceActive = true
    }

    func exitTestingWorkspace() {
        isTestingWorkspaceActive = false
    }
#endif

    private func apply(_ state: AuthenticationState) {
        self.state = state
        switch state {
        case .signedIn, .signedOut:
            operation = nil
            message = nil
        case .failed(let failure):
            operation = nil
            message = failure
        case .loading:
            break
        }
    }

    private func record(_ error: any Error) {
        operation = nil
        if let backendError = error as? BackendError, backendError == .cancelled {
            return
        }
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationErrorDomain,
           nsError.code == ASAuthorizationError.Code.canceled.rawValue {
            return
        }
        message = "We couldn’t finish that sign-in. Please try again."
    }
}

struct VowbaseAppRoot: View {
    let dependencies: AppDependencies
    @State private var coordinator: AuthenticationCoordinator

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _coordinator = State(initialValue: AuthenticationCoordinator(auth: dependencies.auth))
    }

    var body: some View {
        Group {
#if DEBUG
            if coordinator.isTestingWorkspaceActive {
                VowbaseAuthenticatedContent(testingWorkspace: true) {
                    coordinator.exitTestingWorkspace()
                }
            } else {
                authenticationContent
            }
#else
            authenticationContent
#endif
        }
    }

    @ViewBuilder
    private var authenticationContent: some View {
        if case .signedIn = coordinator.state {
            VowbaseAuthenticatedContent(
                repositories: dependencies.repositories,
                onSignOut: coordinator.signOut
            )
        } else if coordinator.state == .loading {
            VowbaseLoadingView(
                title: "Opening Vowbase",
                detail: "Getting everything ready"
            )
        } else {
#if DEBUG
            AuthenticationSignInView(coordinator: coordinator)
#else
            AuthenticationSignInView(coordinator: coordinator)
#endif
        }
    }
}

struct VowbaseLoadingView: View {
    let title: String
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [VowbaseTheme.blush.opacity(0.78), VowbaseTheme.background],
                center: .center,
                startRadius: 16,
                endRadius: 310
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
                    let cycle = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.8) / 1.8
                    let pulse = reduceMotion ? 0.0 : sin(cycle * .pi * 2)

                    ZStack {
                        Circle()
                            .fill(VowbaseTheme.blush.opacity(0.86))
                            .frame(width: 142, height: 142)
                            .scaleEffect(1 + pulse * 0.025)

                        Circle()
                            .stroke(VowbaseTheme.rose.opacity(0.14), lineWidth: 1)
                            .frame(width: 116, height: 116)

                        Circle()
                            .trim(from: 0.04, to: 0.7)
                            .stroke(
                                AngularGradient(
                                    colors: [VowbaseTheme.rose.opacity(0.08), VowbaseTheme.rose],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 116, height: 116)
                            .rotationEffect(.degrees(reduceMotion ? 32 : cycle * 360))

                        Circle()
                            .fill(VowbaseTheme.rose)
                            .frame(width: 8, height: 8)
                            .offset(y: -58)
                            .rotationEffect(.degrees(reduceMotion ? 32 : cycle * 360))
                            .shadow(color: VowbaseTheme.rose.opacity(0.35), radius: 5)

                        VowbaseMark(size: 78)
                            .shadow(color: VowbaseTheme.rose.opacity(0.12), radius: 18, y: 8)
                    }
                    .frame(width: 150, height: 150)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(VowbaseTheme.ink)

                    Text(detail)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(VowbaseTheme.mutedInk)
                }
                .multilineTextAlignment(.center)
            }
            .padding(32)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(detail)
        }
    }
}

private struct AuthenticationLoadingView: View {
    var body: some View {
        VowbaseLoadingView(
            title: "Opening Vowbase",
            detail: "Getting everything ready"
        )
    }
}

private struct AuthenticationSignInView: View {
    @Bindable var coordinator: AuthenticationCoordinator

    var body: some View {
        ZStack {
            VowbaseTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VowbaseMark(size: 92)
                    .padding(.bottom, 30)

                Text("Plan the day\nyou’ll remember")
                    .font(.system(size: 42, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VowbaseTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your venues, your guests, and every decision in one beautiful place.")
                    .font(.system(size: 17))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .padding(.top, 16)
                    .padding(.horizontal, 36)

                Spacer(minLength: 42)

                VStack(spacing: 13) {
                    Button {
                        coordinator.signInWithGoogle()
                    } label: {
                        AuthenticationButtonLabel(
                            title: coordinator.operation == .google ? "Connecting…" : "Continue with Google"
                        )
                    }
                    .buttonStyle(AuthenticationButtonStyle())
                    .disabled(coordinator.isSigningIn || coordinator.operation == .signOut)
                    .accessibilityHint("Opens Google securely to sign in")

                    SignInWithAppleButton(.continue) { request in
                        coordinator.prepareAppleRequest(request)
                    } onCompletion: { result in
                        coordinator.completeAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(coordinator.isSigningIn || coordinator.operation == .signOut)
                    .accessibilityHint("Uses your Apple account to sign in")

#if DEBUG
                    Button {
                        coordinator.enterTestingWorkspace()
                    } label: {
                        TestingAuthenticationButtonLabel()
                    }
                    .buttonStyle(AuthenticationButtonStyle())
                    .disabled(coordinator.isSigningIn || coordinator.operation == .signOut)
                    .accessibilityIdentifier("continue-with-testing")
                    .accessibilityHint("Opens a local workspace populated with testing data")
#endif
                }
                .padding(.horizontal, 24)

                if let message = coordinator.message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(VowbaseTheme.rose)
                        .padding(.horizontal, 28)
                        .padding(.top, 18)

                    if case .failed = coordinator.state {
                        Button("Try again") {
                            coordinator.retry()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VowbaseTheme.rose)
                        .padding(.top, 8)
                    }
                }

                Text("By continuing, you agree to Vowbase’s Terms and Privacy Policy.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .padding(.horizontal, 38)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
            }
        }
    }
}

struct VowbaseConfigurationErrorView: View {
    var body: some View {
        ZStack {
            VowbaseTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                VowbaseMark(size: 78)
                Text("Vowbase needs to be configured")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VowbaseTheme.ink)
                Text("Add the Supabase and API values to your local configuration, then relaunch the app.")
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VowbaseTheme.mutedInk)
                    .padding(.horizontal, 32)
            }
            .padding(24)
        }
    }
}

private struct AuthenticationButtonLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            GoogleSignInIcon()
            Text(title)
                .font(.system(size: 20, weight: .medium))
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 18)
    }
}

#if DEBUG
private struct TestingAuthenticationButtonLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "testtube.2")
                .font(.system(size: 18, weight: .medium))
                .accessibilityHidden(true)
            Text("Continue with Testing")
                .font(.system(size: 20, weight: .medium))
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 54)
        .padding(.horizontal, 18)
    }
}
#endif

private struct GoogleSignInIcon: View {
    var body: some View {
        Image("Theme=Light, Show text=No, Shape=Square, Platform=iOS")
            .resizable()
            .interpolation(.high)
            .frame(width: 44, height: 44)
            .frame(width: 20, height: 20)
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct AuthenticationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VowbaseTheme.border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.74 : 1)
    }
}

struct VowbaseMark: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? "VowbaseIcon-iOS-Dark-1024x1024" : "VowbaseIcon-iOS-Default-1024x1024")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.223, style: .continuous))
    }
}

private enum AuthenticationNonce {
    static func make() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

#Preview("Sign in") {
    AuthenticationSignInView(coordinator: .init(auth: AuthenticationPreviewAuthService()))
}

#Preview("Opening") {
    AuthenticationLoadingView()
}

#Preview("Configuration required") {
    VowbaseConfigurationErrorView()
}

#Preview("Sign-in error") {
    AuthenticationSignInErrorPreview()
}

private struct AuthenticationSignInErrorPreview: View {
    @State private var coordinator: AuthenticationCoordinator

    init() {
        let coordinator = AuthenticationCoordinator(auth: AuthenticationErrorPreviewAuthService())
        coordinator.state = .failed("Authentication state unavailable.")
        coordinator.message = "We couldn’t finish that sign-in. Please try again."
        _coordinator = State(initialValue: coordinator)
    }

    var body: some View {
        AuthenticationSignInView(coordinator: coordinator)
    }
}

private final class AuthenticationPreviewAuthService: AuthServicing, @unchecked Sendable {
    let states = AsyncStream<AuthenticationState> { continuation in
        continuation.yield(.signedOut)
    }

    func currentAccessToken() async throws -> String { "" }
    func refreshSession() async throws {}
    func handle(url: URL) async throws {}
    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {}
    func signOut() async throws {}
}

private final class AuthenticationErrorPreviewAuthService: AuthServicing, @unchecked Sendable {
    let states = AsyncStream<AuthenticationState> { _ in }

    func currentAccessToken() async throws -> String { "" }
    func refreshSession() async throws {}
    func handle(url: URL) async throws {}
    func signInWithIDToken(
        provider: OpenIDConnectCredentials.Provider,
        token: String,
        nonce: String?
    ) async throws {}
    func signOut() async throws {}
}
