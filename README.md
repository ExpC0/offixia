# Offixia

**A focused office operations and communication app for Android.**

Offixia brings attendance, leave, tasks, teams, announcements, messaging, and
peer-to-peer calls into one organization-scoped workspace. It is built with
Flutter and Firebase, with authorization enforced in both the interface and
Cloud Firestore Security Rules.

> Status: actively developed and distributed by direct APK installation. It is
> not currently published to an app store.

## Product experience

The interface uses a purpose-built light and dark design system, bundled Inter
fonts, calm surface hierarchy, and restrained motion. No font or visual asset
is downloaded at runtime. Publication screenshots are intentionally omitted
until a fresh demo organization can be captured without employee details,
organization access codes, notifications, or device identifiers.

## What Offixia does

### Organization and people

- Create an organization or join one with a six-character code.
- Invite a new employee by email with their initial designation, department,
  and job title already assigned.
- Give every employee a stable, human-readable staff number.
- Search the directory and maintain reporting lines, departments, job titles,
  phone numbers, roles, and account status.
- Delegate a specific authority without promoting the employee's designation.
- Let employees leave an organization; let only its founder delete it.

### Attendance and workday

- Check in and out with a server timestamp and location fix.
- Optionally restrict attendance to a configured office geofence.
- Review personal history, monthly totals, and role-appropriate team views.
- Flag late arrivals against the organization's configured start.
- Enforce a nine-hour office day: eight working hours plus a one-hour break.
  The organization may choose a start time from 08:00 through 09:00, so the
  corresponding end time is 17:00 through 18:00.

### Leave, tasks, and announcements

- Request leave by type and inclusive date range, then follow its approval
  state and decision note.
- Route direct reports to their manager while allowing authorized company-wide
  approvers to handle the broader queue.
- Assign tasks with assignee, team, priority, due date, and a
  to-do / doing / done workflow.
- Publish and pin company announcements.

### Teams and communication

- Form cross-department teams with a lead and explicit membership.
- Create direct and group conversations with live message delivery, unread
  state, local notifications, deletion of your own messages, group management,
  and blocking for direct threads.
- Place one-to-one audio or video calls.
- Start a group audio or video call from any group conversation. The picker
  allows at most three colleagues, making four phones including the caller.
- Choose earpiece or loudspeaker, mute, disable or switch the camera, and hang
  up locally without waiting for a network round trip.

## Authority model

Offixia separates a person's designation from individually delegated
authority. A grant can add a capability but can never remove one already
conferred by the designation.

| Designation | Authority added by the role |
|---|---|
| Employee | Own attendance, leave, and assigned work; company directory and feeds |
| Manager | Direct-report leave decisions, task assignment, team attendance |
| HR | Company-wide leave decisions, announcements, invitations, people management |
| DGM | Company-wide reporting |
| GM | Team design and individual authority grants |
| MD | Organization settings and organization deletion |

The following authorities can be delegated individually: approve leave,
assign tasks, post announcements, view all attendance, manage people, invite
employees, and manage teams. Only a GM or MD can edit grants. Nobody may assign
a designation at or above their own rank.

The founding MD is the only self-approval exception for leave. This is based on
the founder's identity—not merely an MD title—so a one-person organization can
operate without allowing other senior employees to approve themselves.

## Call security and limits

Offixia calls use WebRTC. Firestore carries only the authenticated signaling
exchange: SDP descriptions, ICE candidates, participant state, and call
timestamps. Audio and video are sent between the participating phones and are
encrypted in transit with WebRTC DTLS-SRTP; media is not uploaded to Firestore.

Security Rules limit a direct call's signaling to its two endpoints. For a
group call, each pair's SDP and ICE candidates are visible only to those two
endpoints—not to every person invited to the call. Join, decline, leave, and
end transitions are append-only or narrowly field-limited, preventing one
client from changing another participant's state.

Group calls use a full peer-to-peer mesh to keep the media path serverless. A
phone must upload one stream for every other participant, so calls are capped
at four devices. Larger calls should move to an SFU with an explicit
application-layer E2EE/key-management design; silently calling server-relayed
media “end-to-end encrypted” would be misleading.

Current builds use public Google STUN servers and do not include a TURN relay.
That keeps infrastructure simple but means calls may fail between restrictive
NATs or enterprise/mobile networks. STUN can observe connection metadata such
as public IP addresses, but it does not receive call media. As with any calling
application, a participant can still capture media on their own device.

## Architecture

```text
lib/
├── main.dart                 Firebase startup and exhaustive session gate
├── theme.dart                light/dark design system and semantic surfaces
├── format.dart               date, time, and duration formatting
├── config.dart               build-time application configuration
├── models/                   immutable Firestore-backed domain models
├── services/                 auth, live data, permissions, and WebRTC logic
├── screens/                  feature screens and call experiences
└── widgets/                  shared cards, states, avatars, and status UI
```

State is deliberately lightweight: singleton services, `ValueNotifier`, and
Firestore streams consumed by `StreamBuilder`. There is no Provider, Riverpod,
or Bloc layer.

`SessionService` resolves the live chain from Firebase Authentication to the
user's membership, organization, and employee record. The result is one sealed
state: loading, signed out, needs organization, suspended, ready, or failed.
The app gate switches over it exhaustively, so introducing a new state without
handling it is a compile-time error.

### Firestore layout

```text
memberships/{uid}                         user's current organization
joinCodes/{code}                          pre-membership organization lookup
joinAttempts/{uid}                        short-lived private code proof
invites/{normalizedEmail}                 role-aware email invitation
organizations/{orgId}
├── employees/{uid}                       identity, role, grants, reporting line
├── attendance/{uid}_{yyyy-MM-dd}         one record per person per day
├── leaveRequests/{requestId}
├── tasks/{taskId}
├── announcements/{announcementId}
├── teams/{teamId}
├── chats/{chatId}
│   └── messages/{messageId}
├── calls/{callId}                        direct-call signaling
└── groupCalls/{callId}                   group state and pair signaling
    └── peers/{sortedUidPair}
        ├── offerCandidates/{candidateId}
        └── answerCandidates/{candidateId}
```

The employee document ID is the Firebase Auth UID. That lets a Security Rule
answer “what may this caller do?” with one document lookup. Attendance IDs
combine UID and date, making one record per employee per day structural rather
than a convention. Direct chat IDs are derived from two sorted UIDs, so both
people resolve the same conversation without a race or duplicate thread.

## Security design

The Dart permission model controls what the interface offers;
`firestore.rules` is the real enforcement boundary. Important invariants
include:

- Every organization subtree is tenant-scoped and requires active membership.
- Creating or joining an organization is atomic: the organization, employee,
  membership, invite/code proof, and staff-number counter must agree in the
  same write. A client cannot mint its own membership or privileged role.
- Role changes, individual grants, invitations, and organization deletion have
  separate, least-privilege rules.
- Attendance creation uses `request.time`; a client cannot backdate arrival.
- Check-out and approval writes may change only their documented fields.
- Chat membership is the conversation ACL, messages are server-stamped, and
  message bodies cannot be edited after sending.
- WebRTC signaling is restricted to the relevant call participants and ICE
  candidates are append-only.
- Android signing credentials, Firebase environment configuration,
  service-account credentials, logs, and build artifacts are ignored by Git.
- Release tasks fail unless `android/key.properties` explicitly identifies a
  signing key; the project never silently publishes with Flutter's debug key.
- Android App Check uses Play Integrity by default. Firebase's debug provider
  is available only through an explicit build-time development flag.

No review can prove that software has zero defects. The repeatable checks in
this repository cover static correctness, domain rules, release compilation,
APK signature verification, and Firestore rule review; device tests cover the
OS, permission, audio-route, and network behavior that unit tests cannot.

Please report suspected vulnerabilities through GitHub's private vulnerability
reporting flow described in [`SECURITY.md`](SECURITY.md), never through a
public issue.

## Getting started

### Prerequisites

- Flutter 3.44.8 / Dart 3.12.2
- JDK 17
- Android SDK with API 37 available
- A Firebase project with Authentication and Cloud Firestore
- An Android device or emulator running API 24 or newer

This project intentionally caps Gradle/Kotlin memory in
`android/gradle.properties` so release builds remain reliable on an 8 GB
development machine.

### Firebase configuration

1. Register an Android app with package name `com.rian.offixia`.
2. Download `google-services.json` into `android/app/`. The file is
   intentionally ignored so a clone cannot accidentally build against the
   production Firebase project. It contains public client identifiers, not an
   Admin SDK or service-account key, but environment separation still matters.
3. Enable Google as a Firebase Authentication provider.
4. Register both the SHA-1 and SHA-256 fingerprints of every signing
   certificate used to install the app.
5. Supply the OAuth web client ID if the default project is not being used:

   ```bash
   flutter run \
     --dart-define=GOOGLE_SERVER_CLIENT_ID=<oauth-client-id>
   ```

Deploy the database rules and indexes from the repository root:

```bash
firebase deploy --only firestore --project <firebase-project-id>
```

For production App Check, register the Android app with the Play Integrity
provider, link the Google Play project, and monitor valid requests before
enabling enforcement. Directly distributed builds need the Play Integrity
settings appropriate for off-Play installs. Local development may use a
Firebase-registered debug token with an explicit opt-in:

```bash
flutter run --dart-define=OFFIXIA_APP_CHECK_DEBUG=true
```

Never use that flag for a published build.

### Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

### Release signing

Create a private keystore once and protect it as a release credential. Never
commit the keystore or its passwords.

```bash
keytool -genkeypair -v \
  -keystore /secure/path/offixia-upload.jks \
  -alias offixia \
  -keyalg RSA -keysize 4096 -validity 10000

cp android/key.properties.example android/key.properties
```

Edit the ignored `android/key.properties` with the absolute keystore path,
alias, and passwords. Then build the ARM64 APK used by the test devices:

```bash
flutter build apk \
  --release \
  --target-platform android-arm64 \
  --build-number=<incremented-version-code>
```

The artifact is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Verification

The local quality gate is:

```bash
flutter analyze
flutter test
npm --prefix firestore_test ci
firebase emulators:exec --only firestore \
  --project demo-offixia \
  "npm --prefix firestore_test test"
flutter build apk --release --target-platform android-arm64
git diff --check
```

Automated tests currently cover the role ladder, grant behavior, leave
decision boundaries, office-hour invariants, employee formatting, attendance
identity/durations, inclusive leave days, and task overdue behavior. Firestore
emulator tests additionally cover organization-entry forgery, join codes,
invites, suspended accounts, employee attendance, direct-message creation,
chat departure, and recursive signaling cleanup. Calling still requires
two-device testing because microphone focus, OEM audio routing, ringtone policy,
NAT traversal, and remote hang-up behavior live below Flutter's unit-test
boundary.

GitHub Actions repeats the Flutter and Firestore gates on every change. Action
dependencies are pinned to immutable commit SHAs, the Gradle wrapper and
distribution are checksum-pinned, and dependency review rejects vulnerable
dependency changes in public pull requests. CodeQL analyzes workflow code
after the repository becomes public; CodeQL does not currently support Dart
itself.

## Technology

- Flutter and Dart
- Firebase Authentication
- Cloud Firestore with Security Rules and composite indexes
- WebRTC via `flutter_webrtc`
- Android local notifications
- Geolocator and runtime permission handling

## Repository notes

- Package: `com.rian.offixia`
- Minimum Android API: 24
- Primary release target: Android ARM64
- Firebase project selection is kept in `.firebaserc`. Firebase's Android
  client configuration contains public project identifiers rather than a
  server credential; signing keys and service-account credentials stay local.
