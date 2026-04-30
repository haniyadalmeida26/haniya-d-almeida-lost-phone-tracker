# Mobile App

This Flutter app powers both:

- the tracked Android phone experience
- the Chrome/web controller dashboard

## What it includes

- Login and registration flow
- Lost Mode screen
- Alarm handling UI
- History and map views
- Finder scan workflow
- Theme and dashboard experience used in the project demo

## Run locally

```powershell
cd D:\lost-phone-tracker\mobile-app
flutter pub get
flutter run -d chrome
```

For Android device testing:

```powershell
cd D:\lost-phone-tracker\mobile-app
flutter run -d <DEVICE_ID>
```
