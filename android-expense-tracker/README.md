# Expense Tracker (Android)

A native Android app for tracking monthly expenses. Kotlin + Jetpack Compose + Room, no backend or network required — everything is stored locally on-device.

## Features

- Add, edit, and delete expenses (amount, category, date, optional note)
- Browse expenses month by month
- Monthly total and a per-category spending breakdown
- 8 built-in categories: Food, Transport, Shopping, Bills, Entertainment, Health, Education, Other

## Requirements

- Android Studio (Ladybug or newer recommended)
- JDK 17
- Android SDK with `compileSdk 35` / `targetSdk 35` installed (Android Studio will prompt to install if missing)

## Build & run

Open this `android-expense-tracker/` directory in Android Studio and let it sync, or from the command line:

```bash
./gradlew assembleDebug
```

The resulting APK is written to `app/build/outputs/apk/debug/`.

## Project structure

```
app/src/main/java/com/expensetracker/app/
  data/        Room entity, DAO, database, repository
  ui/          ViewModel, theme, reusable composables (ui/components), screens (ui/screens)
  navigation/  Navigation Compose graph
  MainActivity.kt, ExpenseApp.kt
```

Data persists in a local Room/SQLite database (`expense_tracker.db`); there's no sync or cloud storage.
