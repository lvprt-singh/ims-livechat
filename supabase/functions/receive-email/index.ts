// supabase/functions/receive-email/index.ts
// Resend inbound webhook → fetch full email → extract token → insert message.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const CHAT_DOMAIN = "independentmotorsports.com.au";
const FROM_EMAIL = `chat@${CHAT_DOMAIN}`;

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    console.log("Inbound webhook type:", body.type);

    if (body.type !== "email.received") {
      return new Response("Ignored", { status: 200 });
    }

    const webhook = body.data ?? body;
    const emailId = webhook.email_id;
    if (!emailId) {
      console.error("No email_id");
      return new Response("No email_id", { status: 200 });
    }

    const fullEmail = await fetchFullEmail(emailId);
    if (!fullEmail) {
      console.log("All fetch URLs failed, using fallback");
      return await handleWithoutBody(webhook);
    }

    console.log("Got full email, subject:", fullEmail.subject);
    return await processEmail(fullEmail);
  } catch (err) {
    console.error("Fatal:", err);
    return new Response(`Error: ${err}`, { status: 500 });
  }
});

async function processEmail(fullEmail: any): Promise<Response> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  const fromEmail = extractEmail(fullEmail.from);
  if (!fromEmail) return new Response("No sender", { status: 200 });

  if (fromEmail.toLowerCase().endsWith(`@${CHAT_DOMAIN}`)) {
    console.log("Self-send ignored:", fromEmail);
    return new Response("Self-send", { status: 200 });
  }

  const messageId = fullEmail.message_id ?? null;
  if (messageId) {
    const { data: existing } = await supabase
      .from("messages").select("id").eq("email_message_id", messageId).maybeSingle();
    if (existing) {
      console.log("Duplicate:", messageId);
      return new Response("Duplicate", { status: 200 });
    }
  }

  const token = extractToken(fullEmail);
  console.log("Token:", token);

  if (!token) {
    await sendAutoReply(fromEmail, fullEmail.subject ?? "your email");
    return new Response("No token", { status: 200 });
  }

  const { data: chat } = await supabase
    .from("chats").select("id, status").eq("email_token", token).maybeSingle();

  if (!chat) {
    console.log("No chat for token:", token);
    await sendAutoReply(fromEmail, fullEmail.subject ?? "your email");
    return new Response("Chat not found", { status: 200 });
  }

  const cleanText = stripQuotedReply(fullEmail.text ?? "");
  if (!cleanText) {
    console.log("Empty after stripping. Raw:", fullEmail.text?.slice(0, 200));
    return new Response("Empty reply", { status: 200 });
  }

  const inReplyToRaw = fullEmail.headers?.["in-reply-to"];
  const inReplyTo = typeof inReplyToRaw === "string" ? inReplyToRaw : null;

  const { error: insertErr } = await supabase.from("messages").insert({
    chat_id: chat.id,
    sender: "customer",
    content: cleanText,
    source: "email",
    email_message_id: messageId,
    email_in_reply_to: inReplyTo,
  });

  if (insertErr) {
    console.error("Insert failed:", insertErr);
    return new Response(`Insert error: ${insertErr.message}`, { status: 500 });
  }

  await supabase.from("chats").update({
    last_message_at: new Date().toISOString(),
    has_unread: true,
    customer_last_seen_at: new Date().toISOString(),
    status: chat.status === "closed" ? "open" : chat.status,
  }).eq("id", chat.id);

  console.log(`Inserted for chat ${chat.id} from ${fromEmail}`);
  return new Response("OK", { status: 200 });
}

// Try multiple URL patterns until one works.
async function fetchFullEmail(emailId: string): Promise<any | null> {
  const candidates = [
    `https://api.resend.com/emails/receiving/${emailId}`,
    `https://api.resend.com/inbound/emails/${emailId}`,
    `https://api.resend.com/receiving/${emailId}`,
    `https://api.resend.com/inbound/${emailId}`,
    `https://api.resend.com/emails/${emailId}`,
  ];

  for (const url of candidates) {
    try {
      const res = await fetch(url, {
        headers: { Authorization: `Bearer ${RESEND_API_KEY}` },
      });
      console.log(`GET ${url} → ${res.status}`);
      if (res.ok) {
        console.log(`✓ Worked: ${url}`);
        return await res.json();
      } else {
        const errText = await res.text();
        console.log(`  error body: ${errText.slice(0, 200)}`);
      }
    } catch (e) {
      console.error(`Exception for ${url}:`, e);
    }
  }
  return null;
}

// Fallback: can't fetch body, but use webhook subject/from to at least record a placeholder.
async function handleWithoutBody(webhook: any): Promise<Response> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  const subject = webhook.subject ?? "";
  const tokenMatch = subject.match(/\[(c_[a-zA-Z0-9]+)\]/);
  if (!tokenMatch) {
    console.log("Fallback: no token in subject");
    return new Response("No token", { status: 200 });
  }

  const token = tokenMatch[1];
  const { data: chat } = await supabase
    .from("chats").select("id").eq("email_token", token).maybeSingle();

  if (!chat) return new Response("Chat not found", { status: 200 });

  const fromEmail = extractEmail(webhook.from) ?? "unknown";
  await supabase.from("messages").insert({
    chat_id: chat.id,
    sender: "customer",
    content: `[Email reply from ${fromEmail} — body unavailable, check Resend dashboard]`,
    source: "email",
    email_message_id: webhook.message_id ?? null,
  });

  await supabase.from("chats").update({
    last_message_at: new Date().toISOString(),
    has_unread: true,
  }).eq("id", chat.id);

  return new Response("Fallback OK", { status: 200 });
}

function extractEmail(raw: string | undefined | null): string | null {
  if (!raw) return null;
  const m = raw.match(/<([^>]+)>/);
  if (m) return m[1].trim().toLowerCase();
  const m2 = raw.match(/[\w.+-]+@[\w.-]+\.[\w]+/);
  return m2 ? m2[0].toLowerCase() : null;
}

function extractToken(email: any): string | null {
  const headerTo = email.headers?.to ?? "";
  const headerToStr = Array.isArray(headerTo) ? headerTo.join(" ") : String(headerTo);
  const plusMatch = headerToStr.match(/chat\+(c_[a-zA-Z0-9]+)@/);
  if (plusMatch) return plusMatch[1];

  const subject = email.subject ?? "";
  const subMatch = subject.match(/\[(c_[a-zA-Z0-9]+)\]/);
  if (subMatch) return subMatch[1];

  return null;
}

function stripQuotedReply(text: string): string {
  if (!text) return "";

  const patterns = [
  /^On [\s\S]+?wrote:/m,                     // Gmail (handles line-wrapped attribution)
  /^-{3,}\s*Original Message\s*-{3,}/im,     // Outlook
  /^From:\s.+\nSent:\s.+\nTo:\s/im,          // Outlook variant
  /^_{5,}/m,                                 // Underscore divider
  /^-{3,}\s*Forwarded message\s*-{3,}/im,    // Forwards
];

  let earliestIdx = text.length;
  for (const p of patterns) {
    const m = text.match(p);
    if (m && m.index !== undefined && m.index < earliestIdx) {
      earliestIdx = m.index;
    }
  }

  let trimmed = text.substring(0, earliestIdx);
  const lines = trimmed.split("\n");
  while (lines.length > 0) {
    const last = lines[lines.length - 1].trim();
    if (last === "" || last.startsWith(">")) lines.pop();
    else break;
  }
  const cleaned = lines.filter(
    (l) => !/^Sent from my (iPhone|iPad|Samsung|Android|mobile)/i.test(l.trim())
  );
  return cleaned.join("\n").trim();
}

async function sendAutoReply(toEmail: string, originalSubject: string) {
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: `Independent Motorsports <${FROM_EMAIL}>`,
        to: toEmail,
        subject: `Re: ${originalSubject}`,
        text: [
          "Hi,",
          "",
          "Thanks for your email — this address only handles replies to existing chat sessions started from our website.",
          "",
          "If you'd like to reach us, please:",
          "• Email sales@independentmotorsports.com.au",
          "• Or use the \"Let's Talk\" chat button on https://www.independentmotorsports.com.au",
          "",
          "Thanks,",
          "Independent Motorsports",
        ].join("\n"),
        headers: { "X-Auto-Response": "no-match" },
      }),
    });
    if (!res.ok) console.error("Auto-reply failed:", res.status, await res.text());
  } catch (e) {
    console.error("Auto-reply exception:", e);
  }
}