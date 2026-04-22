// supabase/functions/send-customer-email/index.ts
// Picks up chats with pending mechanic messages and emails the customer
// the full thread. Fires from pg_cron every minute.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const FROM_EMAIL = "chat@independentmotorsports.com.au";

Deno.serve(async () => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // 1. Find chats that need an email sent
    const { data: chats, error: chatsErr } = await supabase.rpc("chats_needing_email");
    if (chatsErr) {
      console.error("Error fetching chats:", chatsErr);
      return new Response(`RPC error: ${chatsErr.message}`, { status: 500 });
    }

    if (!chats || chats.length === 0) {
      console.log("No chats need emailing");
      return new Response("No pending emails", { status: 200 });
    }

    console.log(`Processing ${chats.length} chat(s) needing email`);

    let sent = 0;
    let failed = 0;

    for (const chat of chats) {
      try {
        // 2. Load full thread history for this chat
        const { data: messages, error: msgErr } = await supabase
          .from("messages")
          .select("id, sender, content, image_url, created_at, pending_email_send")
          .eq("chat_id", chat.id)
          .in("sender", ["customer", "mechanic"])
          .order("created_at", { ascending: true });

        if (msgErr || !messages) {
          console.error(`Error loading messages for chat ${chat.id}:`, msgErr);
          failed++;
          continue;
        }

        // 3. Build plain-text email body
        const body = buildEmailBody(messages, chat);

        // 4. Send via Resend
        const replyTo = `chat+${chat.email_token}@independentmotorsports.com.au`;
        const subject = `A mechanic at Independent Motorsports has replied [${chat.email_token}]`;

        const resendRes = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${RESEND_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: `Independent Motorsports <${FROM_EMAIL}>`,
            to: chat.customer_email,
            reply_to: replyTo,
            subject,
            text: body,
          }),
        });

        if (!resendRes.ok) {
          const errText = await resendRes.text();
          console.error(`Resend failed for chat ${chat.id}:`, resendRes.status, errText);
          failed++;
          continue;
        }

        const resendData = await resendRes.json();
        console.log(`Email sent for chat ${chat.id}, resend id: ${resendData.id}`);

        // 5. Mark all pending mechanic messages as emailed
        const pendingIds = messages
          .filter((m) => m.pending_email_send && m.sender === "mechanic")
          .map((m) => m.id);

        if (pendingIds.length > 0) {
          const { error: updateErr } = await supabase
            .from("messages")
            .update({
              pending_email_send: false,
              email_sent_at: new Date().toISOString(),
              email_message_id: resendData.id ?? null,
            })
            .in("id", pendingIds);

          if (updateErr) {
            console.error(`Failed to mark messages for chat ${chat.id}:`, updateErr);
          }
        }

        // 6. Update chat's last_email_sent_at
        await supabase
          .from("chats")
          .update({ last_email_sent_at: new Date().toISOString() })
          .eq("id", chat.id);

        sent++;
      } catch (err) {
        console.error(`Error processing chat ${chat.id}:`, err);
        failed++;
      }
    }

    return new Response(
      JSON.stringify({ processed: chats.length, sent, failed }),
      { headers: { "Content-Type": "application/json" }, status: 200 }
    );
  } catch (err) {
    console.error("Fatal error:", err);
    return new Response(`Error: ${err}`, { status: 500 });
  }
});

// Build a plain-text email body with full thread history
function buildEmailBody(
  messages: Array<{
    sender: string;
    content: string | null;
    image_url: string | null;
    created_at: string;
  }>,
  chat: { page_url: string | null; customer_name: string | null }
): string {
  const lines: string[] = [];

  lines.push(`Hi ${chat.customer_name || "there"},`);
  lines.push("");
  lines.push("A mechanic at Independent Motorsports has replied to your chat.");
  lines.push("");
  lines.push("You can reply directly to this email and we'll see it.");
  lines.push("");
  lines.push("---");
  lines.push("Conversation history:");
  lines.push("---");
  lines.push("");

  for (const m of messages) {
    const who = m.sender === "customer" ? (chat.customer_name || "You") : "IMS Mechanic";
    const when = formatTime(m.created_at);
    const content = m.content || (m.image_url ? "[image]" : "");
    lines.push(`${who} · ${when}`);
    lines.push(content);
    lines.push("");
  }

  if (chat.page_url) {
    lines.push("---");
    lines.push(`Chat started from: ${chat.page_url}`);
  }

  lines.push("");
  lines.push("Independent Motorsports");
  lines.push("https://www.independentmotorsports.com.au");

  return lines.join("\n");
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString("en-AU", {
    timeZone: "Australia/Melbourne",
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}