// supabase/functions/get-quote-draft/index.ts
// Mechanic app calls this to fetch a submitted draft for prefilling QuoteFormScreen.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const { token } = body;
    if (!token) return new Response("Missing token", { status: 400 });

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    const { data, error } = await supabase
      .from("quote_drafts")
      .select(
        "token, status, title, customer_name, rego, car_type, transmission, work_description, chat_id"
      )
      .eq("token", token)
      .maybeSingle();

    if (error || !data) {
      return new Response("Draft not found", { status: 404 });
    }

    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Error:", err);
    return new Response(`Error: ${err}`, { status: 500 });
  }
});