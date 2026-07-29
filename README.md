# VolleyTrack — Flutter App
AI-powered volleyball player tracking by jersey number.

---

## STEP 1 — Install Dependencies

Open a terminal in this folder and run:
```
flutter pub get
```

---

## STEP 2 — Run on Android (quickest way to test)

1. Enable Developer Mode on your Android phone:
   Settings → About Phone → tap Build Number 7 times
   Then Settings → Developer Options → enable USB Debugging

2. Plug phone into PC via USB, tap Allow when prompted

3. Run:
```
flutter devices     (your phone should appear)
flutter run
```

---

## STEP 3 — Get it on iPhone (via Codemagic, no Mac needed)

### 3a — Push to GitHub
1. Create a free account at github.com
2. Create a new repository called "volleytrack" (no README)
3. In terminal inside this folder run:

```
git init
git add .
git commit -m "Initial VolleyTrack commit"
git remote add origin https://github.com/YOURUSERNAME/volleytrack.git
git branch -M main
git push -u origin main
```

When asked for password, use a Personal Access Token:
GitHub → Settings → Developer Settings → Personal Access Tokens → Generate New Token (classic) → tick "repo" → Generate → copy it

### 3b — Set Up Codemagic
1. Go to codemagic.io and sign up with your GitHub account
2. Click "Add application"
3. Select your volleytrack repository
4. Select "Flutter App" as the project type
5. Click "Finish: Add application"

### 3c — Add iOS Camera Permission
Before building, you need to add camera permission.
In Codemagic's file editor, open ios/Runner/Info.plist
Find the closing </dict> tag and paste this just before it:

```xml
<key>NSCameraUsageDescription</key>
<string>VolleyTrack uses the camera to track players by jersey number.</string>
```

Also open ios/Podfile and make sure the first uncommented line reads:
```
platform :ios, '14.0'
```

### 3d — Build and Install
1. In Codemagic, go to Workflow Editor
2. Platform: iOS
3. Build for: Debug (no Apple Developer account needed for testing)
4. Click "Start new build"
5. Wait ~10-15 minutes
6. When done, scan the QR code on your iPhone
7. Tap Install
8. On iPhone: Settings → General → VPN & Device Management → Trust the developer

---

## HOW DETECTION WORKS

**Jersey Detection**
Every 10 frames, ML Kit OCR scans the camera for 1-2 digit numbers.
When your target number is found, a bounding box locks onto that player.

**Hit Detection**
Tracks the last 15 frames (~0.5 seconds).
Detects when the wrist rises sharply then snaps back down — the spike motion.

**Block Detection**
Detects when both wrists are raised above the nose simultaneously for 5+ consecutive frames.

---

## TUNING DETECTION SENSITIVITY

Edit lib/services/pose_analyser.dart:

Too many false hits → increase these numbers:
  riseAmount > 80   (make it higher, e.g. 100)
  snapDown > 40     (make it higher, e.g. 60)

Missing real hits → decrease those numbers.

Blocks not detected → change:
  framesUp >= 5     (make it lower, e.g. 3)
