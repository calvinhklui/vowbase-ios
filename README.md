# Vowbase

Native SwiftUI iOS app project for Vowbase.

Open `Vowbase.xcodeproj` in Xcode, choose the **Vowbase** scheme, and run it on an iPhone or iPad simulator.

## Configuration

For a local Debug build, copy `Configuration/Local.xcconfig.example` to the
ignored `Configuration/Local.xcconfig` and supply the local runtime values.

Release values live in `Configuration/Release.xcconfig`, so Xcode Cloud needs
no custom script or workflow variables to archive the app. They contain only
client-visible endpoints and the Supabase publishable key. Do not add a
service-role key, OAuth client secret, or any other server-only credential to
the iOS app or repository.

## Authentication

The iOS app intentionally offers only **Continue with Google** and **Continue
with Apple**. It restores the Supabase session on launch and presents the
sign-in screen whenever no session is available. Signing out is available from
the account button in the wedding header.

Before testing either provider, complete this production configuration:

1. In Supabase **Auth → URL Configuration**, add
   `vowbase://auth/callback` to the redirect allow list.
2. In Supabase **Auth → Providers**, enable Google and add its web OAuth
   client ID and client secret. Google is opened in the system’s secure web
   authentication session; no Google secret is stored in the iOS app.
3. Enable Apple in Supabase and enable the **Sign in with Apple** capability
   for the `Mooma.Vowbase` App ID in Apple Developer. The committed
   `Vowbase.entitlements` file carries the matching app entitlement.

Use the app’s custom `vowbase` URL scheme only for the Supabase callback. Do
not add password, email-link, or anonymous providers; they are intentionally
outside Vowbase’s supported login paths.
