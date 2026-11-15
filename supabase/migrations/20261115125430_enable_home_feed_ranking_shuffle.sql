-- Enable controlled ranking variation so the home feed does not restart
-- with an identical deterministic order on every cold launch.
UPDATE public.feed_config
SET value = 15
WHERE key = 'feed_shuffle_amplitude';
