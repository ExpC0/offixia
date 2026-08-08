# Security policy

## Supported version

Security fixes are applied to the latest commit on `main`. Directly installed
APKs should be upgraded to the newest published release before a report is
investigated.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting form under the
repository's **Security** tab. Do not disclose a vulnerability, employee data,
organization access code, Firebase token, network candidate, or proof of
concept in a public issue.

Include the affected app version, Android version, feature, reproduction steps,
and the smallest safe evidence needed to demonstrate impact. Remove employee
names, email addresses, organization identifiers, location data, and call
metadata from attachments.

You should receive an acknowledgement within seven days. A confirmed issue
will be triaged by severity, fixed privately, and disclosed only after users
have a safe upgrade path.

## Scope and design notes

- Cloud Firestore Security Rules—not hidden interface controls—are the backend
  authorization boundary.
- `google-services.json` contains Firebase Android client identifiers that are
  also present in every APK. It is environment-specific and intentionally not
  committed; it must never be confused with an Admin SDK or service-account
  credential.
- Android keystores, signing passwords, service-account files, APKs, and local
  debug tokens must never be committed.
- App Check complements authentication and authorization; it does not replace
  either one.
