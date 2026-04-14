import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const IMS_EMAIL = Deno.env.get("IMS_EMAIL")!;

Deno.serve(async () => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  const tenMinsAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString();

  // Find open chats older than 10 mins, email not yet sent
  const { data: chats, error } = await supabase
    .from("chats")
    .select(`
      id,
      page_url,
      created_at,
      customers (name, phone),
      messages (sender)
    `)
    .eq("status", "open")
    .eq("email_sent", false)
    .lt("created_at", tenMinsAgo);

  if (error) {
    console.error("Error fetching chats:", error);
    return new Response("Error", { status: 500 });
  }

  // Filter to chats where no mechanic has replied
  const unanswered = chats?.filter((chat) =>
    !chat.messages.some((m: { sender: string }) => m.sender === "mechanic")
  );

  if (!unanswered || unanswered.length === 0) {
    return new Response("No unanswered chats", { status: 200 });
  }

  const chatList = unanswered.map((chat) =>
    `- ${chat.customers.name} (${chat.customers.phone}) — ${chat.page_url} — started at ${new Date(chat.created_at).toLocaleString("en-AU", { timeZone: "Australia/Melbourne" })}`
  ).join("\n");

  const emailBody = `The following customers have been waiting over 10 minutes with no reply:\n\n${chatList}\n\nLog into the IMS chat app to respond.`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "chat@independentmotorsports.com.au",
      to: IMS_EMAIL,
      subject: "Unanswered customer chats — IMS Live Chat",
      text: emailBody,
    }),
  });

  if (!res.ok) {
    console.error("Resend error:", await res.text());
    return new Response("Email failed", { status: 500 });
  }

  // Mark all emailed chats so they don't get emailed again
  const ids = unanswered.map((c) => c.id);
  await supabase
    .from("chats")
    .update({ email_sent: true })
    .in("id", ids);

  return new Response(`Email sent for ${unanswered.length} unanswered chats`, { status: 200 });
});