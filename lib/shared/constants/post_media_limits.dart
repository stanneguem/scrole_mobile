/// Limits enforced by the Supabase public.create_post RPC.
/// Keep this client-side value aligned with the Supabase create_post media limit.
/// Video support will share this same combined media budget.
const int maxPostMedia = 20;

/// Backward-compatible alias for image-only UI until video selection is implemented.
const int maxPostPhotos = 4;
