/// Limits enforced by the Supabase public.create_post RPC.
/// Keep this client-side value aligned with the backend's cardinality(v_photos) <= 4 guard.
const int maxPostPhotos = 4;
