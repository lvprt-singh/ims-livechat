// supabase/functions/request-quote-form/index.ts
// Mechanic triggers this. Creates a quote_draft, emails customer with link, inserts chat msg.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const CHAT_DOMAIN = "independentmotorsports.com.au";
const FROM_EMAIL = `chat@${CHAT_DOMAIN}`;
const FORM_BASE_URL = Deno.env.get("QUOTE_FORM_URL") ?? "https://ims-livechat.pages.dev/quote.html";

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const { chat_id, customer_email, chat_email_token } = body;

    if (!chat_id || !customer_email) {
      return new Response("Missing chat_id or customer_email", { status: 400 });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // Generate unique token
    const token = `qd_${crypto.randomUUID().replace(/-/g, "").slice(0, 16)}`;

    // Create draft row
    const { error: insErr } = await supabase.from("quote_drafts").insert({
      chat_id,
      token,
      status: "pending",
    });

    if (insErr) {
      console.error("Insert draft failed:", insErr);
      return new Response(`DB error: ${insErr.message}`, { status: 500 });
    }

    const formUrl = `${FORM_BASE_URL}?t=${token}`;
    const replyTo = `chat+${chat_email_token}@${CHAT_DOMAIN}`;

    // Email customer
    const emailBody = [
      "Hi,",
      "",
      "We'd like to prepare a quote for you. Could you fill in your vehicle details and a short description of the work you need?",
      "",
      `Open the form here: ${formUrl}`,
      "",
      "It only takes a minute. Once submitted, we'll prepare your quote and send it back.",
      "",
      "Independent Motorsports",
      "+61 03 5134 8822",
    ].join("\n");

    const emailRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: `Independent Motorsports <${FROM_EMAIL}>`,
        to: customer_email,
        reply_to: replyTo,
        subject: `Please fill in your vehicle details for a quote [${chat_email_token}]`,
        text: emailBody,
      }),
    });

    if (!emailRes.ok) {
      console.error("Email failed:", await emailRes.text());
    }

    // Chat system message — customer widget + mechanic app render this as a card
    const messageContent = `📝 QUOTE_REQUEST_SENT|${token}|${formUrl}`;
    await supabase.from("messages").insert({
      chat_id,
      sender: "system",
      content: messageContent,
      source: "dashboard",
    });

    await supabase.from("chats").update({
      last_message_at: new Date().toISOString(),
    }).eq("id", chat_id);

    return new Response(JSON.stringify({ ok: true, token, form_url: formUrl }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error:", err);
    return new Response(`Error: ${err}`, { status: 500 });
  }
});