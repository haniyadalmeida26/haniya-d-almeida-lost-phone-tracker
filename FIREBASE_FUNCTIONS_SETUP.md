# Firebase-Only Lost Mode Setup

This project now supports a Firebase-only wake-up flow for Lost Mode.

## What changes

- Chrome controller calls a Firebase Cloud Function named `sendLostModeCommand`
- The Cloud Function sends a high-priority FCM data message to the lost phone
- The lost phone handles that push and starts Lost Mode logic without needing your laptop backend

## One-time setup

Run these commands from the project root:

```powershell
cd D:\lost-phone-tracker
npm install --prefix functions
firebase login
firebase use lost-phone-tracker-781e6
firebase deploy --only functions
```

## App run commands

Phone:

```powershell
cd D:\lost-phone-tracker\mobile
flutter run
```

Chrome controller:

```powershell
cd D:\lost-phone-tracker\mobile
flutter run -d chrome
```

## Important notes

- Open the phone app once after install so it saves its FCM token.
- After the Cloud Function is deployed, same-Wi-Fi is no longer needed for Lost Mode control.
- Both controller and phone only need internet access.
- If Android force-stops the app from system settings, instant wake-up is still not guaranteed.
