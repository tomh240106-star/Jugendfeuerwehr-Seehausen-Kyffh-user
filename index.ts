
import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
const FIREBASE_PRIVATE_KEY = (Deno.env.get("FIREBASE_PRIVATE_KEY") || "").replace(/\\n/g, "\n");

async function getGoogleAccessToken() {
  const now = Math.floor(Date.now() / 1000);
  const key = await importPKCS8(FIREBASE_PRIVATE_KEY, "RS256");

  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(FIREBASE_CLIENT_EMAIL)
    .setSubject(FIREBASE_CLIENT_EMAIL)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`Google OAuth failed: ${await response.text()}`);
  }

  const data = await response.json();
  return data.access_token as string;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response("Unauthorized", { status: 401 });
    }

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userResult } = await userClient.auth.getUser();
    const user = userResult?.user;
    if (!user) {
      return new Response("Unauthorized", { status: 401 });
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profileError || profile?.role !== "ausbilder") {
      return new Response("Forbidden", { status: 403 });
    }

    const payload = await req.json();
    const title = String(payload.title ?? "").trim();
    const body = String(payload.body ?? "").trim();
    const userId = payload.user_id ? String(payload.user_id) : null;

    if (!title || !body) {
      return new Response("title and body are required", { status: 400 });
    }

    let query = admin.from("device_tokens").select("token,user_id");
    if (userId) query = query.eq("user_id", userId);

    const { data: tokens, error: tokenError } = await query;
    if (tokenError) throw tokenError;

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no_tokens" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }

    const accessToken = await getGoogleAccessToken();
    let sent = 0;
    const failed: string[] = [];

    for (const item of tokens) {
      const fcm = await fetch(
        `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: item.token,
              notification: { title, body },
              android: {
                priority: "high",
                notification: { channel_id: "jf_general" },
              },
              apns: {
                payload: { aps: { sound: "default" } },
              },
              data: {
                source: "jf_seehausen_kyffhaeuser",
              },
            },
          }),
        },
      );

      if (fcm.ok) {
        sent++;
      } else {
        failed.push(await fcm.text());
      }
    }

    return new Response(JSON.stringify({ sent, failed_count: failed.length }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: String(error?.message ?? error) }),
      {
        status: 500,
        headers: { "content-type": "application/json" },
      },
    );
  }
});
