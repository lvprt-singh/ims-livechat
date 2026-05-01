// supabase/functions/quote-form-page/index.ts
// GET ?t=<token> → returns HTML form
// POST ?t=<token> → updates draft to 'submitted', inserts chat message, push notif fires

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("t");

  if (!token) {
    return htmlPage(errorPage("Invalid link"));
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  if (req.method === "GET") {
    const { data: draft } = await supabase
      .from("quote_drafts")
      .select("status, customer_name, rego, car_type, transmission, work_description, title")
      .eq("token", token)
      .maybeSingle();

    if (!draft) return htmlPage(errorPage("This link is invalid or has expired."));
    if (draft.status === "submitted" || draft.status === "completed") {
      return htmlPage(submittedPage());
    }
    return htmlPage(formPage(token, draft));
  }

  if (req.method === "POST") {
    const formData = await req.formData();
    const title = (formData.get("title") as string ?? "").trim();
    const customerName = (formData.get("customer_name") as string ?? "").trim();
    const rego = (formData.get("rego") as string ?? "").trim();
    const carType = (formData.get("car_type") as string ?? "").trim();
    const transmission = (formData.get("transmission") as string ?? "").trim();
    const workDesc = (formData.get("work_description") as string ?? "").trim();

    if (!title || !customerName || !workDesc) {
      return htmlPage(errorPage("Please fill in title, name, and description of work."));
    }

    // Check still pending
    const { data: draft } = await supabase
      .from("quote_drafts")
      .select("status, chat_id")
      .eq("token", token)
      .maybeSingle();

    if (!draft) return htmlPage(errorPage("Link not found"));
    if (draft.status !== "pending") return htmlPage(submittedPage());

    // Update draft
    const { error: updErr } = await supabase
      .from("quote_drafts")
      .update({
        status: "submitted",
        title,
        customer_name: customerName,
        rego,
        car_type: carType,
        transmission,
        work_description: workDesc,
        submitted_at: new Date().toISOString(),
      })
      .eq("token", token);

    if (updErr) {
      console.error("Update failed:", updErr);
      return htmlPage(errorPage("Something went wrong, please try again."));
    }

    // Insert chat message — mechanic sees this card; trigger fires push notif
    const messageContent = `📋 QUOTE_DRAFT_SUBMITTED|${token}|${title}|${customerName}`;
    await supabase.from("messages").insert({
      chat_id: draft.chat_id,
      sender: "customer",
      content: messageContent,
      source: "email",
    });

    await supabase.from("chats").update({
      last_message_at: new Date().toISOString(),
      has_unread: true,
    }).eq("id", draft.chat_id);

    return htmlPage(submittedPage());
  }

  return new Response("Method not allowed", { status: 405 });
});

// ─────────────────────────────────────────────────────────────

function htmlPage(html: string): Response {
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

function shellHtml(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0" />
<title>${title}</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #f5f5f7;
    color: #1a1a1a;
    line-height: 1.5;
    padding: 0;
    min-height: 100vh;
  }
  .header {
    background: #c81d24;
    color: white;
    padding: 20px 16px;
    text-align: center;
  }
  .header h1 { font-size: 18px; font-weight: 700; letter-spacing: 0.3px; }
  .header p { font-size: 12px; opacity: 0.85; margin-top: 4px; font-weight: 500; }
  .container {
    max-width: 560px;
    margin: 0 auto;
    padding: 20px 16px 40px;
  }
  .card {
    background: white;
    border-radius: 14px;
    padding: 20px;
    margin-bottom: 14px;
    box-shadow: 0 1px 4px rgba(0,0,0,0.04);
  }
  .card h2 {
    font-size: 12px;
    font-weight: 700;
    color: #555;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 14px;
  }
  label {
    display: block;
    font-size: 13px;
    font-weight: 600;
    color: #444;
    margin-bottom: 6px;
  }
  input, textarea {
    width: 100%;
    padding: 12px 14px;
    border: 1px solid #e0e0e0;
    border-radius: 10px;
    font-size: 15px;
    font-family: inherit;
    background: #fafafa;
    transition: border-color 0.15s, background 0.15s;
  }
  input:focus, textarea:focus {
    outline: none;
    border-color: #c81d24;
    background: white;
  }
  textarea { resize: vertical; min-height: 110px; }
  .field { margin-bottom: 14px; }
  .field:last-child { margin-bottom: 0; }
  button {
    width: 100%;
    padding: 14px;
    background: #c81d24;
    color: white;
    border: none;
    border-radius: 10px;
    font-size: 15px;
    font-weight: 700;
    cursor: pointer;
    transition: background 0.15s;
  }
  button:hover { background: #a51820; }
  button:disabled { background: #ccc; cursor: not-allowed; }
  .info, .success, .error {
    text-align: center;
    padding: 40px 20px;
  }
  .info-icon, .success-icon, .error-icon {
    font-size: 48px;
    margin-bottom: 16px;
  }
  .info h2, .success h2, .error h2 {
    font-size: 20px;
    margin-bottom: 10px;
  }
  .info p, .success p, .error p {
    color: #666;
    font-size: 14px;
  }
  .footer {
    text-align: center;
    margin-top: 24px;
    font-size: 11px;
    color: #999;
  }
  .footer strong { color: #555; }
</style>
</head>
<body>
${body}
</body>
</html>`;
}

function formPage(token: string, draft: any): string {
  const v = (s: string | null | undefined) => (s ?? "").replace(/"/g, "&quot;");
  return shellHtml(
    "Vehicle Details — Independent Motorsports",
    `<div class="header">
      <h1>Independent Motorsports</h1>
      <p>VEHICLE DETAILS FOR YOUR QUOTE</p>
    </div>
    <div class="container">
      <form method="POST" action="?t=${token}">
        <div class="card">
          <h2>What's the job?</h2>
          <div class="field">
            <label for="title">Quote title</label>
            <input type="text" id="title" name="title" placeholder="e.g. Brake replacement" value="${v(draft.title)}" required maxlength="120" />
          </div>
        </div>

        <div class="card">
          <h2>Your details</h2>
          <div class="field">
            <label for="customer_name">Your name</label>
            <input type="text" id="customer_name" name="customer_name" value="${v(draft.customer_name)}" required maxlength="120" />
          </div>
        </div>

        <div class="card">
          <h2>Vehicle</h2>
          <div class="field">
            <label for="rego">Rego</label>
            <input type="text" id="rego" name="rego" placeholder="e.g. ABC123" value="${v(draft.rego)}" maxlength="20" autocapitalize="characters" />
          </div>
          <div class="field">
            <label for="car_type">Make / model</label>
            <input type="text" id="car_type" name="car_type" placeholder="e.g. 2018 Ford Falcon XR6" value="${v(draft.car_type)}" maxlength="120" />
          </div>
          <div class="field">
            <label for="transmission">Transmission</label>
            <input type="text" id="transmission" name="transmission" placeholder="Auto / Manual" value="${v(draft.transmission)}" maxlength="60" />
          </div>
        </div>

        <div class="card">
          <h2>What needs doing?</h2>
          <div class="field">
            <label for="work_description">Describe the work you'd like quoted</label>
            <textarea id="work_description" name="work_description" placeholder="As much detail as you can — what's wrong, any symptoms, when it started, anything you've already tried." required maxlength="2000">${v(draft.work_description)}</textarea>
          </div>
        </div>

        <button type="submit">Send to Mechanic</button>
        <div class="footer">
          <strong>Independent Motorsports</strong><br />
          3/32 Vestan Dr, Morwell VIC 3840<br />
          +61 03 5134 8822
        </div>
      </form>
    </div>`
  );
}

function submittedPage(): string {
  return shellHtml(
    "Submitted — Independent Motorsports",
    `<div class="header"><h1>Independent Motorsports</h1></div>
     <div class="container">
       <div class="card success">
         <div class="success-icon">✓</div>
         <h2>Thanks, we got your details</h2>
         <p>Your mechanic will prepare a quote and send it through soon. You can close this page.</p>
       </div>
     </div>`
  );
}

function errorPage(msg: string): string {
  return shellHtml(
    "Error — Independent Motorsports",
    `<div class="header"><h1>Independent Motorsports</h1></div>
     <div class="container">
       <div class="card error">
         <div class="error-icon">⚠</div>
         <h2>Something's not right</h2>
         <p>${msg}</p>
       </div>
     </div>`
  );
}