# friendlyhood-split

A dark, modern Flutter app for shared wallets, food/travel expense splitting and personal monthly insights. Firebase Authentication and Firebase Realtime Database provide live multi-user updates.

## Product rules

- Any Google-authenticated user can create a group.
- The group creator becomes that group's admin.
- Only the admin can add members, add deposits/expenses, or delete transactions.
- Members have read-only access and can open their personal dashboard.
- Every expense is equally split among the selected members.
- The group wallet is `all contributions - all expenses`.
- Monthly change and the highest-spend category are calculated live from the ledger.

This owner-per-group model avoids unsafe hard-coded admin emails. To transfer ownership later, change `ownerId` and both users' roles using a trusted Cloud Function/Admin SDK—not from the client.

## Firebase setup (required once)

The database URL and Firebase project number are already wired for `friends-split-up`. Firebase still requires the app-specific keys that are generated only after registering each app:

1. In Firebase Console → **Authentication → Sign-in method**, enable **Google**.
2. Register an Android app with package `com.friendlyhood.split` (or use the package shown in your generated Android project). Add SHA-1/SHA-256 for Google login.
3. Download `google-services.json` into `android/app/`.
4. For iOS, register the bundle ID and put `GoogleService-Info.plist` in `ios/Runner/`.
5. Install FlutterFire CLI and run:

   ```powershell
   dart pub global activate flutterfire_cli
   flutterfire configure --project=friends-split-up
   ```

   Let it replace `lib/firebase_options.dart` with the generated real credentials.

6. Deploy the included database rules:

   ```powershell
   firebase use friends-split-up
   firebase deploy --only database
   ```

7. Install packages and run:

   ```powershell
   flutter pub get
   flutter run
   ```

For a web-only quick run without replacing options, pass the Firebase Web App values:

```powershell
flutter run -d chrome --dart-define=FIREBASE_API_KEY=your_key --dart-define=FIREBASE_APP_ID=your_app_id
```

## Realtime Database shape

```text
users/{uid}
groups/{groupId}
  ownerId, name, emoji, createdAt
  members/{uid}: name, email, role
groupMembers/{uid}/{groupId}: true
transactions/{groupId}/{transactionId}
  type, amount, paidBy, splitAmong, category, createdAt
```

To invite someone, they first sign in, tap the ID badge on Home to copy their Member ID, and share it with the group admin. The admin uses the add-member button. This avoids exposing a searchable directory of user emails.

## In-app Android updates (free hosting)

At startup, the app reads `/app_update` from Realtime Database and compares `latestVersionCode` with the installed build number returned by the operating system. Optional updates can be dismissed; forced updates cannot be bypassed. The APK downloads into app-private cache with progress, then Android's normal installer confirmation screen opens.

Firebase Realtime Database stores the update metadata. APK binaries are published as free GitHub Release assets in `santhanamani/friendlyhood-split`, because Firebase Hosting rejects APK executables on the free Spark plan.

Deploy the updated database rules once so update metadata is readable before login:

```powershell
npx.cmd --yes firebase-tools@latest login --no-localhost
npx firebase-tools deploy --only database --project friends-split-up
```

### Publish a future update

1. Increment the version in `pubspec.yaml`, for example `version: 1.0.2+3`. The build number after `+` must always increase.
2. Run the publisher from the project root:

   ```powershell
   .\scripts\publish_update.cmd -Version 1.0.2 -VersionCode 3 -Message "Faster splits and a refreshed dashboard."
   ```

   The `.cmd` wrapper uses `ExecutionPolicy Bypass` only for this one publishing process; it does not weaken or permanently change the Windows system policy. For a forced update, append `-ForceUpdate`:

   ```powershell
   .\scripts\publish_update.cmd -Version 1.0.2 -VersionCode 3 -Message "This update is required." -ForceUpdate
   ```

The script builds the universal release APK using the local signing configuration, uploads it to a GitHub Release, deploys database rules, and updates `/app_update` in Realtime Database. Before the first publish, authenticate both CLIs:

```powershell
gh auth login # optional when Git Credential Manager is already authenticated
npx.cmd --yes firebase-tools@latest login --no-localhost
```

If Firebase says `Already logged in`, no authorization code is needed.

The hosted download URL is:

```text
https://github.com/santhanamani/friendlyhood-split/releases/download/v1.0.2/app-release.apk
```

Every future APK must use the exact same Android signing key as the already-installed app. Android rejects an update signed with a different key. The current Gradle file uses the debug key for release builds only as a development convenience; configure a protected production upload/release keystore before distributing the app to real users, then keep that key permanently.

Android 8+ users are sent to the app-specific **Install unknown apps** settings page when needed. No broad storage permission is requested, and Android always displays its own update confirmation UI.
