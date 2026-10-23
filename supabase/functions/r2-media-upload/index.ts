import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { S3Client, PutObjectCommand } from "npm:@aws-sdk/client-s3@3";
import { getSignedUrl } from "npm:@aws-sdk/s3-request-presigner@3";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

const IMAGE_TYPES: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/avif": "avif",
};
const VIDEO_TYPES: Record<string, string> = { "video/mp4": "mp4", "video/quicktime": "mov" };
const CATEGORIES = new Set([
  "profile_avatar", "profile_cover", "community_avatar", "community_cover",
  "post_media", "story_media", "comment_media", "message_media", "event_media", "bug_report",
]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const accountId = Deno.env.get("R2_ACCOUNT_ID");
  const accessKeyId = Deno.env.get("R2_ACCESS_KEY_ID");
  const secretAccessKey = Deno.env.get("R2_SECRET_ACCESS_KEY");
  const bucket = Deno.env.get("R2_BUCKET_NAME");
  const publicBaseUrl = Deno.env.get("R2_PUBLIC_BASE_URL")?.replace(/\/+$/, "");
  if (!supabaseUrl || !anonKey || !serviceKey) return reply(503, { error: "supabase_not_configured" });
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket || !publicBaseUrl) {
    return reply(503, { error: "r2_not_configured", required_secrets: [
      "R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET_NAME", "R2_PUBLIC_BASE_URL",
    ] });
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return reply(401, { error: "invalid_session" });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (body.action !== "create-upload-url") return reply(400, { error: "unsupported_action" });

  const category = String(body.category ?? (body.media_type === "video" ? "post_media" : ""));
  if (!CATEGORIES.has(category)) return reply(400, { error: "unsupported_category" });
  const mediaType = String(body.media_type ?? "");
  const contentType = String(body.content_type ?? "").toLowerCase().split(";")[0].trim();
  const sizeBytes = Number(body.size_bytes);
  const extension = String(body.extension ?? "").toLowerCase().replace(/^\./, "");
  const entityId = typeof body.entity_id === "string" && body.entity_id.trim() ? body.entity_id.trim() : null;
  const isVideo = mediaType === "video";
  const expectedExtension = (isVideo ? VIDEO_TYPES : IMAGE_TYPES)[contentType];

  if (!expectedExtension || extension !== expectedExtension) {
    return reply(415, { error: "unsupported_media_format", allowed_image_types: Object.keys(IMAGE_TYPES), allowed_video_types: Object.keys(VIDEO_TYPES) });
  }
  if (!Number.isSafeInteger(sizeBytes) || sizeBytes <= 0) return reply(400, { error: "invalid_size" });
  const maxBytes = isVideo ? 100 * 1024 * 1024 : 15 * 1024 * 1024;
  if (sizeBytes > maxBytes) return reply(413, { error: "media_size_limit_exceeded", maximum_bytes: maxBytes });
  const duration = Number(body.duration_seconds);
  if (isVideo && (!Number.isFinite(duration) || duration <= 0 || duration > 30)) {
    return reply(400, { error: "video_duration_limit_exceeded", maximum_seconds: 30 });
  }

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: profile, error: profileError } = await admin
    .from("user_profiles").select("account_status, deleted_at").eq("user_id", user.id).maybeSingle();
  if (profileError) return reply(500, { error: "profile_check_failed" });
  if (!profile || profile.account_status !== "active" || profile.deleted_at !== null) return reply(403, { error: "account_unavailable" });

  // Validate category-specific authorization before signing an upload.
  if (category === "profile_avatar" || category === "profile_cover") {
    if (entityId && entityId !== user.id) return reply(403, { error: "profile_owner_required" });
  } else if (category === "bug_report") {
    // Authenticated active accounts may submit diagnostic screenshots.
  } else if (category === "post_media") {
    if (typeof body.community_id === "string" && body.community_id.trim()) {
      const { data: member, error } = await userClient.rpc("is_community_member", {
        p_community_id: body.community_id.trim(),
      });
      if (error || member !== true) return reply(403, { error: "community_membership_required" });
    }
  } else {
    // Community/event/message authorization depends on schema-specific ownership,
    // moderator and privacy rules. Fail closed until those checks are implemented.
    return reply(501, { error: "category_authorization_not_implemented", category });
  }

  const uploadId = crypto.randomUUID();
  let key: string;
  switch (category) {
    case "profile_avatar": key = `profiles/${user.id}/avatar/${uploadId}.${expectedExtension}`; break;
    case "profile_cover": key = `profiles/${user.id}/cover/${uploadId}.${expectedExtension}`; break;
    case "bug_report": key = `bug-reports/${user.id}/${uploadId}.${expectedExtension}`; break;
    case "post_media":
      key = body.community_id && typeof body.community_id === "string"
        ? `communities/${body.community_id.trim()}/posts/${uploadId}.${expectedExtension}`
        : `posts/${user.id}/${uploadId}.${expectedExtension}`;
      break;
    default: return reply(501, { error: "category_authorization_not_implemented", category });
  }

  const s3 = new S3Client({
    region: "auto",
    endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
    credentials: { accessKeyId, secretAccessKey },
  });
  try {
    const command = new PutObjectCommand({
      Bucket: bucket, Key: key, ContentType: contentType, ContentLength: sizeBytes,
      // Do not sign x-amz-meta-* headers here: the Flutter PUT request does not send
      // those headers, which can make the presigned request fail at R2.

    });
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
    const encodedKey = key.split("/").map(encodeURIComponent).join("/");
    return reply(200, {
      upload_url: uploadUrl, object_key: key, public_url: `${publicBaseUrl}/${encodedKey}`,
      content_type: contentType, size_bytes: sizeBytes, expires_in: 300, max_video_duration_seconds: 30,
    });
  } catch (error) {
    console.error("[r2-media-upload] signed URL generation failed", error);
    return reply(500, { error: "upload_authorization_failed" });
  }
});
