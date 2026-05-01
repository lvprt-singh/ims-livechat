// supabase/functions/submit-quote-draft/index.ts
// Customer's form posts here. Marks draft submitted, inserts chat msg, push fires via trigger.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { token, title, customer_name, rego, car_type, transmission, work_description } = body;

    if (!token || !title?.trim() || !customer_name?.trim() || !work_description?.trim()) {
      return new Response("Missing required fields", { status: 400, headers: corsHeaders });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const { data: draft } = await supabase
      .from("quote_drafts")
      .select("status, chat_id")
      .eq("token", token)
      .maybeSingle();

    if (!draft) return new Response("Not found", { status: 404, headers: corsHeaders });
    if (draft.status !== "pending") {
      return new Response("Already submitted", { status: 409, headers: corsHeaders });
    }

    const { error: updErr } = await supabase
      .from("quote_drafts")
      .update({
        status: "submitted",
        title: title.trim(),
        customer_name: customer_name.trim(),
        rego: (rego ?? "").trim(),
        car_type: (car_type ?? "").trim(),
        transmission: (transmission ?? "").trim(),
        work_description: work_description.trim(),
        submitted_at: new Date().toISOString(),
      })
      .eq("token", token);

    if (updErr) {
      console.error("Update failed:", updErr);
      return new Response(`DB error: ${updErr.message}`, { status: 500, headers: corsHeaders });
    }

    const messageContent = `📋 QUOTE_DRAFT_SUBMITTED|${token}|${title.trim()}|${customer_name.trim()}`;
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

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error:", err);
    return new Response(`Error: ${err}`, { status: 500, headers: corsHeaders });
  }
});