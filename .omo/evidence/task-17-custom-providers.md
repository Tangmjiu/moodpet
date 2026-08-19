# Task 17 — Custom Providers: Dependencies & Android Permissions/Config

**Date:** 2026-08-18
**Project:** /home/mjiutang/moonpet (moodpet)
**Flutter:** 3.44.6 (channel stable) • Dart 3.12.2
**Scope:** Add `qr_flutter` + `mobile_scanner` deps, `integration_test` dev dep, CAMERA permission + local-only cleartext network security config, verify minSdk compatibility.

---

## 1. Dependencies added

### 1a. `flutter pub add qr_flutter mobile_scanner`

Command:
```
flutter pub add qr_flutter mobile_scanner
```
Exit code: **0**

Resolved (from `pubspec.yaml` constraints + `pubspec.lock` versions):
- `qr_flutter`: constraint `^4.1.0` → resolved **4.1.0** (direct main, hosted on pub.dev)
- `mobile_scanner`: constraint `^7.4.0` → resolved **7.4.0** (direct main, hosted on pub.dev)
- transitive: `qr` **3.0.2** (pulled by qr_flutter)

No version conflicts encountered.

`pubspec.yaml` diff (new lines):
```yaml
  qr_flutter: ^4.1.0
  mobile_scanner: ^7.4.0
```

### 1b. `flutter pub add --dev integration_test --sdk flutter`

Command:
```
flutter pub add --dev integration_test --sdk flutter
```
Exit code: **0**

Resolved: `integration_test` **0.0.0** (direct dev, source: sdk/flutter). Pulled transitives: `flutter_driver 0.0.0` (sdk), `fuchsia_remote_debug_protocol 0.0.0` (sdk), `process 5.0.5`, `sync_http 0.3.1`, `webdriver 3.1.0`.

`pubspec.yaml` diff (new dev_dependencies block):
```yaml
  integration_test:
    sdk: flutter
```

### 1c. `pubspec.yaml` grep verification

```
$ grep -nE "qr_flutter|mobile_scanner|integration_test" pubspec.yaml
37:  qr_flutter: ^4.1.0
38:  mobile_scanner: ^7.4.0
44:  integration_test:
```

### 1d. `pubspec.lock` stale-state probe (new deps present in lock)

```
$ grep -A7 "^  mobile_scanner:" pubspec.lock
  mobile_scanner:
    dependency: "direct main"
    description:
      name: mobile_scanner
      sha256: ce3f059ebd6dbfab7292bba0e893e354b46730636820d3c9ef69005ce2d55bce
      url: "https://pub.dev"
    source: hosted
    version: "7.4.0"

$ grep -A7 "^  qr_flutter:" pubspec.lock
  qr_flutter:
    dependency: "direct main"
    description:
      name: qr_flutter
      sha256: "5095f0fc6e3f71d08adef8feccc8cea4f12eec18a2e31c2e8d82cb6019f4b097"
      url: "https://pub.dev"
    source: hosted
    version: "4.1.0"

$ grep -A7 "^  qr:" pubspec.lock
  qr:
    dependency: transitive
    description:
      name: qr
      sha256: "5a1d2586170e172b8a8c8470bbbffd5eb0cd38a66c0d77155ea138d3af3a4445"
      url: "https://pub.dev"
    source: hosted
    version: "3.0.2"

$ grep -A4 "^  integration_test:" pubspec.lock
  integration_test:
    dependency: "direct dev"
    description: flutter
    source: sdk
    version: "0.0.0"
```

Count of new-dep mentions in lock: **5** (mobile_scanner, qr_flutter, qr, integration_test, plus one secondary reference). Lock is fresh — no stale state.

---

## 2. AndroidManifest.xml — CAMERA permission + network security config

### 2a. Original manifest content (quoted verbatim, before edits)

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:label="MoodPet"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:usesCleartextTraffic="false">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

Baseline state: had `INTERNET` permission only; `usesCleartextTraffic="false"` on `<application>`; no CAMERA permission; no `networkSecurityConfig` attribute; no `res/xml/` directory existed.

### 2b. Edits applied

1. Added `<uses-permission android:name="android.permission.CAMERA"/>` immediately after the INTERNET permission (inside `<manifest>`, before `<application>` — NOT inside application).
2. **Kept** `android:usesCleartextTraffic="false"` on the `<application>` tag (unchanged).
3. Added `android:networkSecurityConfig="@xml/network_security_config"` to the `<application>` tag (alongside the kept `usesCleartextTraffic="false"`). The network security config takes precedence over the broad `usesCleartextTraffic` flag for the configured domains, so cleartext is permitted **only** for the local addresses listed in the config and denied everywhere else — global cleartext remains OFF.

### 2c. Verification greps

```
$ grep -n CAMERA android/app/src/main/AndroidManifest.xml
3:    <uses-permission android:name="android.permission.CAMERA"/>

$ grep -n networkSecurityConfig android/app/src/main/AndroidManifest.xml
10:        android:networkSecurityConfig="@xml/network_security_config">
```

### 2d. New file: `android/app/src/main/res/xml/network_security_config.xml`

```
$ cat android/app/src/main/res/xml/network_security_config.xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">10.0.2.2</domain>
    </domain-config>
</network-security-config>
```

`10.0.2.2` is the Android emulator host-loopback alias (so a dev LLM endpoint running on the host machine is reachable via cleartext during local development). `localhost` / `127.0.0.1` cover on-device local servers. `includeSubdomains="false"` on every entry — no subdomain widening.

---

## 3. minSdk compatibility check (mobile_scanner)

### 3a. Project effective minSdk

`android/app/build.gradle.kts` line 22:
```kotlin
minSdk = flutter.minSdkVersion
```

`flutter.minSdkVersion` resolves via the Flutter Gradle plugin extension. Source: Flutter SDK at
`/home/mjiutang/fvm/default/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt` line 26:
```kotlin
val minSdkVersion: Int = 24
```

Also confirmed in the same file: `compileSdkVersion = 36` (line 23), `targetSdkVersion = 36` (line 34).

**Project effective minSdk = 24.**

### 3b. mobile_scanner plugin minSdk requirement

`~/.pub-cache/hosted/pub.dev/mobile_scanner-7.4.0/android/build.gradle` line 58:
```groovy
defaultConfig {
    minSdk = 23
    consumerProguardFiles 'proguard-rules.pro'
}
```
Also: `compileSdk = 36` (line 45) — matches project's `flutter.compileSdkVersion = 36`.

**mobile_scanner 7.4.0 requires minSdk = 23.**

### 3c. Verdict

Project minSdk (24) ≥ plugin floor (23). **No bump needed.** No edits to `build.gradle.kts`.

Proof numbers:
| Item | Value | Source |
|------|-------|--------|
| Project minSdk | 24 | FlutterExtension.kt:26 (via `flutter.minSdkVersion`) |
| mobile_scanner minSdk | 23 | mobile_scanner-7.4.0/android/build.gradle:58 |
| Project compileSdk | 36 | FlutterExtension.kt:23 |
| mobile_scanner compileSdk | 36 | mobile_scanner-7.4.0/android/build.gradle:45 |

---

## 4. Verification commands

### 4a. `flutter pub get`

```
$ flutter pub get
Resolving dependencies...
Downloading packages...
  archive 3.6.1 (4.0.9 available)
  ...
Got dependencies!
12 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
PUBGET_EXIT=0
```
**Exit 0.** The "12 packages have newer versions..." line is informational (pre-existing constraints block newer majors); not an error.

### 4b. `flutter analyze`

```
$ flutter analyze
Analyzing moonpet...
No issues found! (ran in 1.6s)
ANALYZE_EXIT=0
```
**Exit 0, no issues.** No pre-existing unrelated analyze issues present.

### 4c. Manifest greps (reproduced from §2c)

```
$ grep -n CAMERA android/app/src/main/AndroidManifest.xml
3:    <uses-permission android:name="android.permission.CAMERA"/>
$ grep -n networkSecurityConfig android/app/src/main/AndroidManifest.xml
10:        android:networkSecurityConfig="@xml/network_security_config">
```

### 4d. network_security_config.xml (reproduced from §2d)

See §2d — file content verified via `cat`.

### 4e. pubspec.yaml deps (reproduced from §1c)

```
$ grep -nE "qr_flutter|mobile_scanner|integration_test" pubspec.yaml
37:  qr_flutter: ^4.1.0
38:  mobile_scanner: ^7.4.0
44:  integration_test:
```

---

## 5. Adversarial probes

| Probe class | Result |
|-------------|--------|
| **Long external commands** (`flutter pub add` may hang/slow) | All three `pub` invocations completed well under 3 min (each ~5–15s). Timeouts set to 300000ms (5 min) as a safety margin. No hang, no blind kill-and-retry needed. |
| **Stale state** (pubspec.lock must reflect new deps after `pub add`) | Probed: `grep -cE "mobile_scanner\|qr_flutter\|integration_test" pubspec.lock` = **5**. Full lock blocks for all four packages (mobile_scanner, qr_flutter, qr transitive, integration_test) present with correct versions and `direct main`/`direct dev`/`transitive` markers. Lock is consistent with pubspec.yaml. No stale state. |
| Other classes (e.g. disk full, network down, permission denied) | n/a — `pub add` downloaded packages successfully and `pub get`/`analyze` ran clean, ruling these out. |

---

## 6. Constraints compliance

- ✅ Did NOT pin versions by hand in `pubspec.yaml` — used `flutter pub add` exclusively; constraints are the caret ranges pub chose (`^4.1.0`, `^7.4.0`).
- ✅ Did NOT touch `linux/`, any `lib/`, or any `test/` file. Only edited: `pubspec.yaml`, `pubspec.lock` (auto), `android/app/src/main/AndroidManifest.xml`, and created `android/app/src/main/res/xml/network_security_config.xml`.
- ✅ Did NOT run any git command.
- ✅ Did NOT enable global cleartext — `usesCleartextTraffic="false"` retained; cleartext restricted to local addresses via `network_security_config.xml`.
- ✅ No version conflict occurred, so no relax-and-pin fallback was needed.

---

## 7. Files changed

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `qr_flutter: ^4.1.0`, `mobile_scanner: ^7.4.0` (dependencies); added `integration_test: { sdk: flutter }` (dev_dependencies). |
| `pubspec.lock` | Auto-updated by pub; new entries for mobile_scanner 7.4.0, qr_flutter 4.1.0, qr 3.0.2, integration_test 0.0.0 (+ transitives). |
| `android/app/src/main/AndroidManifest.xml` | Added CAMERA `<uses-permission>`; added `android:networkSecurityConfig="@xml/network_security_config"` to `<application>` (kept `usesCleartextTraffic="false"`). |
| `android/app/src/main/res/xml/network_security_config.xml` | **New file.** Local-only cleartext permit for localhost / 127.0.0.1 / 10.0.2.2. |

No changes to `android/app/build.gradle.kts` (minSdk already satisfies plugin).

---

## 8. DoneClaim

```json
{
  "task_id": "17",
  "title": "Custom Providers: dependencies & Android permissions/config",
  "status": "done",
  "evidence_file": ".omo/evidence/task-17-custom-providers.md",
  "changes": [
    "pubspec.yaml: +qr_flutter ^4.1.0, +mobile_scanner ^7.4.0, +integration_test (dev, sdk flutter)",
    "pubspec.lock: resolved mobile_scanner 7.4.0, qr_flutter 4.1.0, qr 3.0.2, integration_test 0.0.0",
    "android/app/src/main/AndroidManifest.xml: +CAMERA permission, +networkSecurityConfig attr (usesCleartextTraffic=false kept)",
    "android/app/src/main/res/xml/network_security_config.xml: new file, local-only cleartext (localhost/127.0.0.1/10.0.2.2)"
  ],
  "verification": {
    "flutter_pub_get_exit": 0,
    "flutter_analyze_exit": 0,
    "analyze_issues": "No issues found!",
    "camera_permission_grep": "3:    <uses-permission android:name=\"android.permission.CAMERA\"/>",
    "network_security_config_grep": "10:        android:networkSecurityConfig=\"@xml/network_security_config\">",
    "pubspec_deps_grep": "37: qr_flutter ^4.1.0 / 38: mobile_scanner ^7.4.0 / 44: integration_test",
    "minsdk_project": 24,
    "minsdk_mobile_scanner_required": 23,
    "minsdk_bump_required": false,
    "minsdk_bump_applied": false
  },
  "residual_risks": []
}
```
