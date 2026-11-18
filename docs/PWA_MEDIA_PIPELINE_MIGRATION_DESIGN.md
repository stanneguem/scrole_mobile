# PWA media pipeline migration — implementation design

## Current branch snapshot

Branch: `feature/story-video-post-reshare`

The previous PWA audit identified direct `dart:io` use. This pass inspected the concrete media pipeline and its consumers before changing public signatures.

## Confirmed current contracts

- `MediaService` returns `File?` from image selection, crop and compression. It directly imports `dart:io`, `path_provider`, `flutter_image_compress` and `image_cropper`.
- `StorageRepository` accepts `File` for Supabase uploads and all R2 convenience methods.
- `R2MediaRepository.uploadFile` accepts `File`, derives extension from `file.path`, reads the entire file into memory with `readAsBytes()`, then streams slices of that already-buffered byte array to R2. Chunked HTTP writes therefore do not currently make file reading memory-streamed.
- `image_picker` is already a dependency and returns `XFile`; no additional dependency is needed merely to represent a picked file.

## Verified consumer impact

| Consumer | Current coupling |
|---|---|
| `CreateAccountController` | `Rxn<File>`, MediaService pick methods, profile avatar/cover uploads |
| `CreateEventController` | `Rx<File?>` cover and MediaService |
| `EditEventController` | MediaService and file-based cover state |
| `CreateCommunityScreen` | creates `File(files.first.path)`, uses `Image.file` |
| `BugReportController` | `Rxn<File>`, converts picker `XFile` to `File`, uploads screenshot |
| `StoriesController` | direct File/path operations, image compression and several R2 uploads |
| `CreateStoryScreen` | stores selected media as `File`, checks file extension and renders local files |
| `ChatController` | already receives `XFile` for picker media in at least one path; message media upload flow needs separate review |

The event creation/edit and community flows have additional screen-level `FileImage` / `Image.file` usage. They must be converted to a cross-platform preview strategy (for example `Image.memory` with cached bytes, or a dedicated XFile preview widget), not just have their imports removed.

## Recommended target contract

Use `XFile` as the boundary type for selected media, because it is already provided by `image_picker` and supports `readAsBytes()`, `length()`, `name`, and `openRead()` across supported platforms.

1. `MediaService` should return `XFile?` for selection/crop/compression. Platform-specific crop/compression must live behind conditional imports. Native implementations may continue using `File`; Web must use browser-compatible bytes/blob handling and must never import `dart:io`.
2. `StorageRepository` and `R2MediaRepository` should accept `XFile` (or a small project-owned media payload carrying XFile, filename and MIME type). Keep a temporary native compatibility wrapper only if needed during staged consumer migration.
3. R2 upload should use the media name/MIME supplied by the payload, validate size before transfer, and avoid reading large videos fully into memory where the HTTP and signing APIs permit a stream. If the Edge Function requires exact `size_bytes`, obtain it via `XFile.length()` before requesting the signed URL.
4. Use `Image.memory` for previews after reading selected image bytes once, or a reusable conditional preview widget. Do not construct `File(path)` on Web.
5. Keep native crop/compress behavior unchanged while providing a Web-compatible fallback. Do not silently report successful crop/compression if the browser implementation did not perform it.
6. Migrate all consumers in one coordinated series of commits, then remove the legacy `File` public APIs once all call sites are converted.

## Why the public API was not changed in this pass

Changing `MediaService` return types or the repository upload parameter from `File` to `XFile` without converting every state holder, preview widget and upload caller would leave the mobile app uncompilable. Conversely, adding a Web-only implementation while common controllers still import `dart:io` would not make the Web target compile. This design pass intentionally avoids landing a partial API break.

## Next implementation sequence

1. Introduce the shared media payload/preview abstraction and conditional native/Web media processing.
2. Convert account creation, event create/edit, community creation and bug-report screenshot selection/upload.
3. Convert Stories/Scut media handling and upload paths; retain their existing cache/outbox semantics.
4. Convert remaining media viewers, editors and gallery screens that use `File`, `Image.file`, `FileImage`, or `VideoPlayerController.file`.
5. Run `flutter analyze`, native build and `flutter build web`; then browser-test picking, preview, upload, cancellation, logout and quota behavior.

## Validation status

This is a source-level design and call-site inspection only. No Flutter analyze, Android build, Web build or browser test was run as part of this pass.


## Outgoing chat attachment blobs

Outgoing chat attachments no longer need to be serialized as Base64 Data URIs in
SQLite. The chat controller writes each selected attachment to the dedicated
Hive box `pending_chat_media` and stores a compact `pending-media://` reference
in the message and outbox payload. Hive uses browser storage on Flutter Web
(IndexedDB-backed) and its native storage backend on mobile. The regular
`app_cache` box is deliberately not used, so ordinary cache clearing does not
erase pending attachments.

The messaging repository resolves these references to `MediaAsset` instances
when processing the outbox and uploads them through the existing R2 media
pipeline. Legacy Data URI payloads remain readable for messages already queued
before this change. The local blob is removed only after the server confirms
message insertion and the outbox row is removed.

A failed upload or message insertion keeps the original reference and blob so
the outbox can retry after reconnection. If the process crashes after R2 upload
but before message insertion, a retry may upload the object again; this favors
recoverability over a broken local attachment. Orphan cleanup, quota management,
streaming large files without buffering, and browser restart/quota tests remain
follow-up work. The current 30 MiB per-attachment limit remains in place.

Validation status: source changes only. Flutter analyze, Android/Web builds,
browser IndexedDB persistence, offline/restart replay, and R2 upload were not
executed in this change.


## Streaming pending chat attachments — follow-up implementation

The pending chat media store now persists selected files as independent binary
chunks (256 KiB target size) in the dedicated `pending_chat_media` Hive LazyBox. The LazyBox reads chunks on demand instead of eagerly loading the entire attachment collection into memory.
The controller passes the picked `XFile` stream to the store instead of calling
`readAsBytes()` for images/videos before persistence. The store checks the
source length against the existing 30 MiB per-attachment limit and verifies
the exact number of bytes written before publishing the manifest/reference.

`MediaAsset` now also supports a stream-backed source. When the outbox retries
a pending attachment, the store returns a stream-backed asset; the existing
R2 upload implementation reads `MediaAsset.openRead()` and sends it through
`http.StreamedRequest` with the known content length. This avoids rebuilding a
whole video byte array during the offline-to-R2 upload path. Older single-blob
pending records and legacy Data URI messages remain readable.

Important remaining constraints:
- Voice recording now writes incoming PCM chunks directly to the dedicated
  LazyBox through a serialized writer. On stop, the WAV header is generated
  from the final PCM length and streamed ahead of the stored chunks when the
  attachment is read. The send/outbox upload path no longer builds a complete
  WAV byte array. Voice review still materializes a Data URI when playback is
  requested, so review playback is not yet fully streaming.
- The pending-media preview helper still materializes a Data URI for
  image/video preview and share flows. Large pending video previews can
  therefore still use substantial memory even though upload is streamed.
- Hive writes one record per chunk; actual browser storage quota, transaction
  performance, and crash recovery during a partially written attachment must
  be measured in a real browser.
- Expired/orphan chunk collection is not yet automated.
- The 30 MiB attachment limit is unchanged.

## Validation status after streaming change

Source inspection confirms the upload path consumes the stream-backed
`MediaAsset.openRead()` API and supplies the known byte length to the R2
streamed request. No Flutter SDK/build runner or repository CI workflow is
available through the current GitHub branch snapshot, and no local build,
analyzer, Android device test, browser IndexedDB test, or live R2 transfer was
run. These changes must be validated locally before release.


## Streamed voice recording follow-up

Direct-message voice capture no longer retains the full PCM recording in a
controller-side `List<int>`. Each recorder chunk is appended sequentially to
the pending-media LazyBox in 256 KiB records. Once recording stops, the store
publishes a WAV manifest with the final size; the WAV header is generated
lazily when `MediaAsset.openRead()` is consumed, followed by the persisted PCM
chunks. The existing outbox/R2 upload path therefore reads the recording as a
stream. Cancellation removes the staged chunks, and failed writes prevent the
manifest from being published.

Voice review currently resolves the pending WAV to a Data URI on demand for
the audio player. Pending image previews and share/save flows can still
materialize data in memory. Pending video playback now resolves the stored
MediaAsset directly: native platforms stream it into a temporary file and
delete that file when the video controller is disposed. The current Web
fallback still materializes a Data URI; a browser Blob/object-URL adapter with
explicit lifetime cleanup remains follow-up work.

Validation remains source-only: no Flutter analyzer, Android/Web build,
microphone capture, browser IndexedDB, device playback, offline replay or R2
transfer was executed.
