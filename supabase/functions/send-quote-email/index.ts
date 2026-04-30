// supabase/functions/send-quote-email/index.ts
// Receives PDF bytes from app, uploads to storage, emails customer with attachment,
// inserts a system message in chat with link to PDF.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const CHAT_DOMAIN = "independentmotorsports.com.au";
const FROM_EMAIL = `chat@${CHAT_DOMAIN}`;

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const {
      chat_id,
      customer_email,
      chat_email_token,
      quote_number,
      customer_name,
      quote_by,
      total,
      pdf_base64,
    } = body;

    console.log("Received body keys:", Object.keys(body));
console.log("chat_id:", chat_id, "customer_email:", customer_email, "pdf_base64 len:", pdf_base64?.length);

if (!chat_id || !customer_email || !pdf_base64) {
  const missing = [];
  if (!chat_id) missing.push("chat_id");
  if (!customer_email) missing.push("customer_email");
  if (!pdf_base64) missing.push("pdf_base64");
  return new Response(`Missing: ${missing.join(", ")}`, { status: 400 });
}

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // 1. Decode PDF and upload to storage
    const pdfBytes = Uint8Array.from(atob(pdf_base64), (c) => c.charCodeAt(0));
    const filename = `${chat_id}/${quote_number}.pdf`;

    const { error: uploadErr } = await supabase.storage
      .from("quotes")
      .upload(filename, pdfBytes, {
        contentType: "application/pdf",
        upsert: true,
      });

    if (uploadErr) {
      console.error("Upload failed:", uploadErr);
      return new Response(`Upload error: ${uploadErr.message}`, { status: 500 });
    }

    // 2. Get public URL
    const { data: urlData } = supabase.storage.from("quotes").getPublicUrl(filename);
    const pdfUrl = urlData.publicUrl;

    // 3. Email the customer with PDF attached
    const replyTo = `chat+${chat_email_token}@${CHAT_DOMAIN}`;
    const subject = `Your quote from Independent Motorsports [${chat_email_token}]`;

    const emailBody = [
      `Hi ${customer_name || "there"},`,
      "",
      `Please find attached your quote ${quote_number} from Independent Motorsports.`,
      "",
      `Total: $${Number(total).toFixed(2)}`,
      "",
      "Note: This is an indicative price and subject to change. A final quote would be sent upon agreement. This quote is valid for 7 days.",
      "",
      "Reply to this email if you'd like to proceed or have any questions.",
      "",
      `Quote prepared by: ${quote_by}`,
      "",
      "Independent Motorsports",
      "3/32 Vestan Dr, Morwell VIC 3840",
      "+61 03 5134 8822",
    ].join("\n");

    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: `Independent Motorsports <${FROM_EMAIL}>`,
        to: customer_email,
        reply_to: replyTo,
        subject,
        text: emailBody,
        attachments: [
          {
            filename: `${quote_number}.pdf`,
            content: pdf_base64,
          },
        ],
      }),
    });

    if (!resendRes.ok) {
      const err = await resendRes.text();
      console.error("Resend failed:", resendRes.status, err);
      return new Response(`Email send failed: ${err}`, { status: 500 });
    }

    // 4. Insert a system message in chat with quote URL
    const messageContent = `📄 QUOTE_SENT|${quote_number}|${pdfUrl}|$${Number(total).toFixed(2)}`;
    await supabase.from("messages").insert({
      chat_id,
      sender: "system",
      content: messageContent,
      source: "dashboard",
    });

    await supabase.from("chats").update({
      last_message_at: new Date().toISOString(),
    }).eq("id", chat_id);

    return new Response(JSON.stringify({ ok: true, pdf_url: pdfUrl }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error:", err);
    return new Response(`Error: ${err}`, { status: 500 });
  }
});