# PuppyPay Admin Alert App (Flutter)

Blinkit/Uber-style **instant** push for new **deposit + withdraw** orders.

## Features
- High-priority FCM (sound + vibration even when app is killed)
- **Alerts ON/OFF** (class mode)
- Login with existing admin username/password
- Pending deposits & withdrawals list + Accept/Reject
- Test notification button

## Setup (one-time)

### 1) Firebase
1. Go to [Firebase Console](https://console.firebase.google.com) → Create project `PuppyPay`
2. Add **Android app** with package name: `com.puppypay.admin`
3. Download `google-services.json` → put in `android/app/`
4. Project Settings → **Service accounts** → Generate new private key (JSON)
5. Vercel backend env:
   - `FIREBASE_SERVICE_ACCOUNT` = entire JSON as **one line string**
   - (optional) `FIREBASE_PROJECT_ID` = your project id
6. Redeploy backend so `firebase-admin` installs

### 2) Flutter
```bash
# Install Flutter: https://docs.flutter.dev/get-started/install
flutter create --org com.puppypay --project-name admin .
# Or clone this repo and:
flutter pub get
# Place google-services.json in android/app/
flutter run
# Release APK:
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### 3) Phone
- Install APK
- Login with admin credentials
- Allow notifications when asked
- Keep **Alerts ON**
- Tap **Test alert** once

## Class mode
Toggle **Alerts OFF** — no sound/vibration/push until you turn ON again.

## API
Default API: `https://puppy-pay-backend.vercel.app/api/admin`
