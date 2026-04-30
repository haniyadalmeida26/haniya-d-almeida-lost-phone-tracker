# Lost Phone Tracker

Lost Phone Tracker is a multi-surface prototype for locating, flagging, and recovering a missing phone. It combines a Flutter mobile app, a web controller experience, a Node backend, and Firebase Cloud Functions for push-driven lost-mode behavior.

## Project Overview

- Mark a device as lost from the web dashboard
- Trigger lost-mode behavior on the tracked phone
- Store last known location, history, and AI prediction hints
- Support finder detections, including trusted-contact priority
- Show map and history views for device recovery workflows

## Clean Repository Structure

```text
lost-phone-tracker/
|-- mobile-app/          # Flutter app for phone + Chrome controller
|-- backend-server/      # Express/Node backend APIs
|-- cloud-functions/     # Firebase Cloud Functions for wake-up commands
|-- docs/                # Setup and architecture notes
|-- firebase.json        # Firebase deployment config
`-- README.md            # Project overview and setup
```

## Tech Stack

- Flutter
- Firebase Auth
- Cloud Firestore
- Firebase Cloud Messaging
- Firebase Cloud Functions
- Node.js / Express
- OpenStreetMap

## Key Features

- Remote Lost Mode from the Chrome controller
- Dedicated red emergency screen for the lost phone
- Alarm triggering and stop controls
- Last-known-location tracking
- Offline detection and prediction hints
- Finder scan workflow with trusted-contact priority
- Firebase-only remote wake architecture for internet-connected devices

## Local Development

### Mobile app

```powershell
cd D:\lost-phone-tracker\mobile-app
flutter pub get
flutter run -d chrome
```

### Backend server

```powershell
cd D:\lost-phone-tracker\backend-server
npm install
npm start
```

### Cloud Functions

```powershell
cd D:\lost-phone-tracker
npm install --prefix cloud-functions
firebase deploy --only "functions"
```

## Environment and Secret Safety

This repository intentionally does **not** include live private backend credentials.

Ignored locally:

- `backend-server/.env`
- `backend-server/serviceAccountKey.json`

Tracked mobile Firebase and web placeholders are masked in the public repo version. Restore your local working values only on your own machine.

Use the template file below for local backend configuration:

- [backend-server/.env.example](backend-server/.env.example)

## Documentation

- [Firebase functions setup](docs/FIREBASE_FUNCTIONS_SETUP.md)
- [Implementation guide](docs/IMPLEMENTATION_GUIDE.md)

## Author

Haniya D Almeida
