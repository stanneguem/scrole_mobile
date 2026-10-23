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
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

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
    return reply(503, { error: "r2_not_configured", required_secrets: ["R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET_NAME", "R2_PUBLIC_BASE_URL"] });
  }
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return reply(401, { error: "authentication_required" });
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return reply(401, { error: "invalid_session" });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_json" }); }
  if (body.action !== "create-upload-url") return reply(400, { error: "unsupported_action" });
  const communityId = typeof body.community_id === "string" && body.community_id.length ? body.community_id : null;
  const mediaType = body.media_type;
  const contentType = body.content_type;
  const sizeBytes = Number(body.size_bytes);
  const duration = Number(body.duration_seconds);
  const extension = String(body.extension ?? "").toLowerCase();
  if (mediaType !== "video") return reply(400, { error: "unsupported_media_type" });
  if (contentType !== "video/mp4" && contentType !== "video/quicktime") return reply(415, { error: "unsupported_video_format", allowed: ["video/mp4", "video/quicktime"] });
  if (!Number.isSafeInteger(sizeBytes) || sizeBytes <= 0 || sizeBytes > 100 * 1024 * 1024) return reply(413, { error: "video_size_limit_exceeded", maximum_bytes: 104857600 });
  if (!Number.isFinite(duration) || duration <= 0 || duration > 30) return reply(400, { error: "video_duration_limit_exceeded", maximum_seconds: 30 });
  if ((extension !== "mp4" && extension !== "mov") || (extension === "mp4" && contentType !== "video/mp4") || (extension === "mov" && contentType !== "video/quicktime")) return reply(400, { error: "extension_content_type_mismatch" });

  if (communityId) {
    const { data: member, error: memberError } = await userClient.rpc("is_community_member", { p_community_id: communityId });
    if (memberError) return reply(403, { error: "community_membership_check_failed" });
    if (member !== true) return reply(403, { error: "community_membership_required" });
  }
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: profile, error: profileError } = await admin.from("user_profiles").select("account_status, deleted_at").eq("user_id", user.id).maybeSingle();
  if (profileError) return reply(500, { error: "profile_check_failed" });
  if (!profile || profile.account_status !== "active" || profile.deleted_at !== null) return reply(403, { error: "account_unavailable" });

  const objectKey = communityId ? `communities/${communityId}/posts/videos/${crypto.randomUUID()}.${extension}` : `users/${user.id}/posts/videos/${crypto.randomUUID()}.${extension}`;
  const s3 = new S3Client({ region: "auto", endpoint: `https://${accountId}.r2.cloudflarestorage.com`, credentials: { accessKeyId, secretAccessKey } });
  try {
    const command = new PutObjectCommand({ Bucket: bucket, Key: objectKey, ContentType: contentType, ContentLength: sizeBytes });
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });
    return reply(200, { upload_url: uploadUrl, object_key: objectKey, public_url: `${publicBaseUrl}/${objectKey.split("/").map(encodeURIComponent).join("/")}`, expires_in: 300, maximum_duration_seconds: 30 });
  } catch (error) {
    console.error("[r2-media-upload] signed URL generation failed", error);
    return reply(500, { error: "upload_authorization_failed" });
  }
});
