# Vowbase

Native SwiftUI iOS app project for Vowbase.

Open `Vowbase.xcodeproj` in Xcode, choose the **Vowbase** scheme, and run it on an iPhone or iPad simulator.

## Configuration

For a local Debug build, copy `Configuration/Local.xcconfig.example` to the
ignored `Configuration/Local.xcconfig` and supply the local runtime values.

For Xcode Cloud Release archives, `ci_scripts/ci_post_clone.sh` generates the
ignored `Configuration/Cloud.xcconfig` from these workflow environment
variables:

- `VOWBASE_PRODUCTION_SUPABASE_URL`
- `VOWBASE_PRODUCTION_SUPABASE_PUBLISHABLE_KEY`
- `VOWBASE_PRODUCTION_API_URL`

Do not commit either generated configuration file. Use a Supabase publishable
key only; service-role keys and other server-only credentials must never enter
the iOS app or Xcode Cloud workflow.
