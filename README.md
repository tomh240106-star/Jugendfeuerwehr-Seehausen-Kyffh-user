
# send-push Edge Function

Benötigte Secrets in Supabase:

- FIREBASE_PROJECT_ID
- FIREBASE_CLIENT_EMAIL
- FIREBASE_PRIVATE_KEY

Supabase stellt zusätzlich typischerweise bereit:
- SUPABASE_URL
- SUPABASE_ANON_KEY
- SUPABASE_SERVICE_ROLE_KEY

Deployment:

```bash
supabase functions deploy send-push
```

Secrets setzen:

```bash
supabase secrets set FIREBASE_PROJECT_ID="..."
supabase secrets set FIREBASE_CLIENT_EMAIL="..."
supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

Die Function akzeptiert nur eingeloggte Benutzer mit Rolle `ausbilder`.
