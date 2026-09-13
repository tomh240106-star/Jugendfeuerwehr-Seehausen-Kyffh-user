
# Firebase Cloud Messaging einrichten

## 1. Firebase-Projekt
In Firebase ein neues Projekt anlegen und eine Android-App registrieren.

Empfohlene Android Package-ID:
`de.jfseehausen.kyffhaeuser`

## 2. Android-Konfiguration
Aus Firebase `google-services.json` herunterladen.

Für GitHub Actions:
Datei lokal Base64-kodieren und den Inhalt als GitHub Secret
`GOOGLE_SERVICES_JSON_BASE64` speichern.

Zusätzlich als GitHub Secrets:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

## 3. Firebase Service Account für serverseitigen Push
In Google Cloud/Firebase einen Service Account für Firebase Cloud Messaging verwenden.
Benötigt werden:
- project_id
- client_email
- private_key

Diese Werte als Supabase Edge Function Secrets speichern:
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Diese geheimen Werte dürfen NICHT in den Flutter-Quellcode.

## 4. Supabase Function deployen
Ordner:
`supabase/functions/send-push`

Dann:
```bash
supabase functions deploy send-push
```

## 5. Test
- App auf Android-Gerät installieren
- anmelden
- Gerätetoken wird in `device_tokens` gespeichert
- mit Ausbilderkonto unter "Ausbilderbereich" -> "Push-Nachricht senden"
- Nachricht an einzelne Person oder alle senden

## iOS
Für iOS zusätzlich APNs-Schlüssel/Zertifikat in Firebase konfigurieren.
Ein echter iOS-Build benötigt macOS/Xcode.
