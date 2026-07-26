# iOS invitation acceptance integration prerequisite

The repository contract tests prove that iOS invokes only `accept_invitation(_token)` and never writes `wedding_memberships` directly. A live acceptance test is intentionally not included because that RPC mutates an invitation and membership row, and this checkout has no isolated invitation-provisioning endpoint or dedicated disposable token.

To run one non-production acceptance flow, provision a fresh, email-null invitation in an isolated staging/test Supabase project for a dedicated test user; record its new token only in ephemeral CI secrets; authenticate the dedicated user; invoke `SupabaseInvitationRepository.accept(token:)`; then verify the returned wedding ID and the server-created active membership. Revoke or delete the isolated test fixture afterward. Do not point this procedure at production or reuse a shared token.
