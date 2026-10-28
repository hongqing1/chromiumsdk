# safe_browsing_mode=0 final-link fix

## Failure
SOLINK `libwebviewchromium.so` failed with undefined symbols when
`safe_browsing_mode=0` (privacy args):

- `safe_browsing::RealTimeUrlChecksAllowlist::GetInstance/IsInAllowlist`
  referenced by `remote_database_manager.cc` (always built for AW)
  while GN only compiles the allowlist target when `safe_browsing_mode==2`.
- `safe_browsing::RendererURLLoaderThrottle::RendererURLLoaderThrottle`
  referenced by `aw_url_loader_throttle_provider.cc` while
  `//components/safe_browsing/content/renderer:throttles` is empty when
  `safe_browsing_mode==0`.

Android defaults to mode 2, so upstream does not exercise mode 0 for WebView.

## Fix (keep mode=0)
Guard call sites with existing buildflags (no SB enablement, no stubs that
reintroduce Google lookups):

- `SAFE_BROWSING_DB_REMOTE` around RealTimeUrlChecksAllowlist usage → no-op
  `is_match=false` when mode=0.
- `SAFE_BROWSING_AVAILABLE` around RendererURLLoaderThrottle construction →
  skip throttle when mode=0.

Patches: `patches/safe-browsing-mode0-*.patch`
