import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const FIREBASE_SERVICE_ACCOUNT = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!;

async function getAccessToken(): Promise<string> {
  const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
  const now = Math.floor(Date.now() / 1000);

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = (obj: object) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");

  const unsigned = `${enc(header)}.${enc(payload)}`;

  const pemContents = sa.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned)
  );

  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const jwt = `${unsigned}.${sig}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) {
    throw new Error(`Token error: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token;
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record;

    if (!record || record.sender !== "customer") {
      return new Response("Not a customer message", { status: 200 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const { data: tokens } = await supabase
      .from("fcm_tokens")
      .select("token");

    if (!tokens || tokens.length === 0) {
      console.log("No FCM tokens found");
      return new Response("No FCM tokens", { status: 200 });
    }

    console.log(`Found ${tokens.length} FCM tokens`);

    const accessToken = await getAccessToken();
    console.log("Got Firebase access token");

    const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
    const projectId = sa.project_id;

    const { data: chat } = await supabase
  .from("chats")
  .select("page_url, customers(name, phone)")
  .eq("id", record.chat_id)
  .single();

const customerName = (chat?.customers as { name?: string; phone?: string })?.name ?? "Customer";
const customerPhone = (chat?.customers as { name?: string; phone?: string })?.phone ?? "";
const messageText = record.content ?? "Sent an image";

    console.log(`Sending notification to ${tokens.length} devices for ${customerName}`);

    for (const { token } of tokens) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
  message: {
    token,
    notification: {
      title: `New message from ${customerName}`,
      body: messageText,
    },
    data: {
  chat_id: record.chat_id,
  customer_name: customerName,
  customer_phone: customerPhone,
  page_url: chat?.page_url ?? "",
},
    android: {
      priority: "high",
      notification: {
        sound: "default",
        channel_id: "ims_chat",
      },
    },
  },
}),
        }
      );

      const result = await res.json();
      console.log(`FCM response: ${JSON.stringify(result)}`);
    }

    return new Response("Notifications sent", { status: 200 });
  } catch (err) {
    console.error("Error:", err);
    return new Response(`Error: ${err}`, { status: 500 });
  }
});