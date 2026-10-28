# Chromium embed AAR — privacy / anti-telemetry GN args

Applied in `src/out/AarArm64/args.gn` for CN store compliance
(关闭遥测 / 上报 / Google 服务相关编译开关).

| Arg | Value | Why |
|-----|-------|-----|
| is_chrome_branded | false | Chromium branding, not Google Chrome |
| use_official_google_api_keys | false | Do not bake official Google keys |
| google_api_key / client id/secret | "invalid" | No usable baked-in keys |
| enable_reporting | false | Disable NEL / Reporting API uploads |
| disable_fieldtrial_testing_config | true | No baked field-trial testing config |
| safe_browsing_mode | 0 | No Safe Browsing / Google lookups |
| enable_remoting | false | No remoting stack |
| enable_hangout_services_extension | false | No Hangouts extension |
| enable_mdns | false | No mDNS discovery |
| enable_updater | false | No auto-updater |
| enable_widevine | false | No Widevine CDM / license phone-home |
| enable_silent_java_assert_reporting | false | No silent Java assert → crash upload |

## Not set / caveat

- `enable_vr = false` **cannot** be used on this target: `//device/vr/public/cpp` asserts `enable_vr` and is pulled via `chrome/browser/permissions`. Left at default.
- GN flags strip many compile-time paths. After AAR is built, re-audit strings for `google.com` metrics/crash endpoints if store review requires. Host app must not enable metrics at runtime.
