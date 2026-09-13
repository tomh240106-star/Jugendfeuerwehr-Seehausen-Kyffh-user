
# Android APK automatisch mit GitHub Actions bauen

Dieses Projekt enthält:
`.github/workflows/android-build.yml`

## Benötigte GitHub Secrets
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `GOOGLE_SERVICES_JSON_BASE64`

Danach:
1. Projekt in GitHub Repository hochladen.
2. Unter Actions den Workflow `Android Build` starten.
3. Nach erfolgreichem Build die Artefakte herunterladen:
   - `jf-seehausen-apk`
   - `jf-seehausen-aab`

Die APK ist direkt für Tests auf Android geeignet.
Das AAB ist für den Google Play Store vorgesehen.
