document.addEventListener("DOMContentLoaded", function () {
  const SUPABASE_URL = "https://lfeaeufshnclbabmxlhc.supabase.co";
  const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxmZWFldWZzaG5jbGJhYm14bGhjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxMTA0MjMsImV4cCI6MjA5MTY4NjQyM30.EMrSYJmK5vitwZsCd8_so8WfvARlR9C96BxZHBo-FPs";

  // Inject Supabase JS
  function loadScript(src, callback) {
    const script = document.createElement("script");
    script.src = src;
    script.onload = callback;
    document.head.appendChild(script);
  }

  // Inject styles
  const style = document.createElement("style");
  style.innerHTML = `
    #ims-chat-btn {
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: #e8261d;
      color: white;
      border: none;
      border-radius: 50px;
      padding: 14px 22px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      z-index: 99999;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
      font-family: sans-serif;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    #ims-chat-btn:hover { background: #c41f17; }
    #ims-chat-panel {
      position: fixed;
      bottom: 90px;
      right: 24px;
      width: 340px;
      max-height: 520px;
      background: white;
      border-radius: 16px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.2);
      z-index: 99999;
      display: none;
      flex-direction: column;
      font-family: sans-serif;
      overflow: hidden;
    }
    #ims-chat-panel.open { display: flex; }
    #ims-chat-header {
      background: #e8261d;
      color: white;
      padding: 16px;
      font-weight: 700;
      font-size: 15px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    #ims-chat-header span { font-size: 12px; font-weight: 400; opacity: 0.85; }
    #ims-chat-close { cursor: pointer; font-size: 20px; line-height: 1; }
    #ims-chat-messages {
      flex: 1;
      overflow-y: auto;
      padding: 16px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      background: #f5f5f5;
    }
    .ims-msg {
      max-width: 80%;
      padding: 10px 14px;
      border-radius: 18px;
      font-size: 14px;
      line-height: 1.4;
      word-break: break-word;
    }
    .ims-msg.customer {
      background: #e8261d;
      color: white;
      align-self: flex-end;
      border-bottom-right-radius: 4px;
    }
    .ims-msg.mechanic {
      background: white;
      color: #222;
      align-self: flex-start;
      border-bottom-left-radius: 4px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
    }
    .ims-msg img { max-width: 200px; border-radius: 8px; display: block; }
    #ims-chat-input-area {
      padding: 12px;
      border-top: 1px solid #eee;
      display: flex;
      gap: 8px;
      align-items: center;
      background: white;
    }
    #ims-chat-input {
      flex: 1;
      border: 1px solid #ddd;
      border-radius: 20px;
      padding: 10px 14px;
      font-size: 14px;
      outline: none;
      resize: none;
    }
    #ims-chat-send {
      background: #e8261d;
      color: white;
      border: none;
      border-radius: 50%;
      width: 38px;
      height: 38px;
      cursor: pointer;
      font-size: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    #ims-chat-image-btn {
      background: none;
      border: none;
      cursor: pointer;
      font-size: 20px;
      color: #999;
      padding: 0;
    }
    #ims-chat-start {
      padding: 20px;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    #ims-chat-start input {
      border: 1px solid #ddd;
      border-radius: 8px;
      padding: 10px 14px;
      font-size: 14px;
      outline: none;
      width: 100%;
      box-sizing: border-box;
    }
    #ims-chat-start button {
      background: #e8261d;
      color: white;
      border: none;
      border-radius: 8px;
      padding: 12px;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
    }
    #ims-chat-start p {
      font-size: 13px;
      color: #666;
      margin: 0;
      text-align: center;
    }
    #ims-typing {
      font-size: 12px;
      color: #999;
      padding: 0 16px 8px;
      display: none;
      background: #f5f5f5;
    }
  `;
  document.head.appendChild(style);

  // Build widget HTML
  document.body.insertAdjacentHTML("beforeend", `
    <button id="ims-chat-btn">💬 Let's Talk</button>
    <div id="ims-chat-panel">
      <div id="ims-chat-header">
        <div>
          <div>Independent Motorsports</div>
          <span>We usually reply within a few hours</span>
        </div>
        <div id="ims-chat-close">✕</div>
      </div>
      <div id="ims-chat-start">
        <p>Send us a message and a mechanic will get back to you.</p>
        <input id="ims-start-name" placeholder="Your name" />
        <input id="ims-start-phone" placeholder="Your phone number" type="tel" />
        <button id="ims-start-btn">Start Chat</button>
      </div>
      <div id="ims-chat-messages" style="display:none"></div>
      <div id="ims-typing">Mechanic is typing...</div>
      <div id="ims-chat-input-area" style="display:none">
        <button id="ims-chat-image-btn">📎</button>
        <input type="file" id="ims-image-input" accept="image/*" style="display:none" />
        <textarea id="ims-chat-input" placeholder="Type a message..." rows="1"></textarea>
        <button id="ims-chat-send">➤</button>
      </div>
    </div>
  `);

  let supabase, chatId, customerId, channel;
  let _sending = false;
  const pageUrl = window.location.href;
  const chatBtn = document.getElementById("ims-chat-btn");
if (chatBtn) {
  chatBtn.innerHTML = pageUrl === 'https://www.independentmotorsports.com.au/' ? "💬 Let's Talk" : "💬 Ask About This";
}

  // Load Supabase
  loadScript("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js", () => {
    supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    initSession();
  });

  async function initSession() {
    const savedChatId = localStorage.getItem("ims_chat_id");
    const savedCustomerId = localStorage.getItem("ims_customer_id");
    if (savedChatId && savedCustomerId) {
      // Verify the chat still exists
      const { data, error } = await supabase
        .from("chats")
        .select("id")
        .eq("id", savedChatId)
        .single();
      
      if (error || !data) {
        // Chat doesn't exist anymore, clear localStorage
        localStorage.removeItem("ims_chat_id");
        localStorage.removeItem("ims_customer_id");
        return;
      }
      
      chatId = savedChatId;
      customerId = savedCustomerId;
      showChat();
      loadMessages();
      subscribeToMessages();
    }
  }

  // Toggle panel
  document.getElementById("ims-chat-btn").onclick = () => {
    document.getElementById("ims-chat-panel").classList.toggle("open");
  };
  document.getElementById("ims-chat-close").onclick = () => {
    document.getElementById("ims-chat-panel").classList.remove("open");
  };

  // Start chat
  document.getElementById("ims-start-btn").onclick = async () => {
    const name = document.getElementById("ims-start-name").value.trim();
    const phone = document.getElementById("ims-start-phone").value.trim();
    if (!name || !phone) return alert("Please enter your name and phone number.");

    // Upsert customer
    const { data: customer, error: cErr } = await supabase
      .from("customers")
      .upsert({ name, phone }, { onConflict: "phone" })
      .select()
      .single();
    if (cErr) return console.error(cErr);

    customerId = customer.id;
    localStorage.setItem("ims_customer_id", customerId);

    // Check for existing open chat
    const { data: existingChats } = await supabase
      .from("chats")
      .select("id")
      .eq("customer_id", customerId)
      .eq("status", "open")
      .order("created_at", { ascending: false })
      .limit(1);

    if (existingChats && existingChats.length > 0) {
      chatId = existingChats[0].id;
      // Log the page the customer returned from
      await supabase.from("messages").insert({
        chat_id: chatId,
        sender: "system",
        content: `📍 Customer returned from: ${pageUrl}`,
        source: "widget",
      });
    } else {
      const { data: chat, error: chatErr } = await supabase
        .from("chats")
        .insert({ customer_id: customerId, page_url: pageUrl })
        .select()
        .single();
      if (chatErr) return console.error(chatErr);
      chatId = chat.id;
    }

    localStorage.setItem("ims_chat_id", chatId);

    showChat();
    loadMessages();
    subscribeToMessages();
  };

  function showChat() {
    document.getElementById("ims-chat-start").style.display = "none";
    document.getElementById("ims-chat-messages").style.display = "flex";
    document.getElementById("ims-chat-input-area").style.display = "flex";
  }

  async function loadMessages() {
    const { data: messages } = await supabase
      .from("messages")
      .select("*")
      .eq("chat_id", chatId)
      .order("created_at", { ascending: true });
    messages?.forEach(renderMessage);
  }

  function subscribeToMessages() {
    channel = supabase
      .channel("chat-" + chatId)
      .on("postgres_changes", {
        event: "INSERT",
        schema: "public",
        table: "messages",
        filter: `chat_id=eq.${chatId}`,
      }, (payload) => {
        renderMessage(payload.new);
      })
      .subscribe();
  }

  function renderMessage(msg) {
    if (msg.sender === "system") return;
    const div = document.createElement("div");
    div.className = `ims-msg ${msg.sender}`;
    if (msg.image_url) {
      div.innerHTML = `<img src="${msg.image_url}" alt="image" />`;
    } else {
      div.textContent = msg.content;
    }
    document.getElementById("ims-chat-messages").appendChild(div);
    document.getElementById("ims-chat-messages").scrollTop = 99999;
  }

  // Send message
  async function sendMessage(content, imageUrl = null) {
    if (!chatId) return;
    await supabase.from("messages").insert({
      chat_id: chatId,
      sender: "customer",
      content: content || null,
      image_url: imageUrl || null,
      source: "widget",
    });
    await supabase.from("chats").update({ last_message_at: new Date().toISOString(), has_unread: true }).eq("id", chatId);
  }

  document.getElementById("ims-chat-send").onclick = async () => {
    const input = document.getElementById("ims-chat-input");
    if (_sending) return;
  _sending = true;
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    await sendMessage(text);
    _sending = false;
  };

  document.getElementById("ims-chat-input").onkeydown = async (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      if (_sending) return;
    _sending = true;
      const input = document.getElementById("ims-chat-input");
      const text = input.value.trim();
      if (!text) return;
      input.value = ""; 
      await sendMessage(text);
      _sending = false;
    }
  };

  // Image upload
  document.getElementById("ims-chat-image-btn").onclick = () => {
    document.getElementById("ims-image-input").click();
  };

  document.getElementById("ims-image-input").onchange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const fileName = `${chatId}/${Date.now()}-${file.name}`;
    const { data, error } = await supabase.storage
      .from("chat-images")
      .upload(fileName, file);
    if (error) return console.error(error);
    const { data: urlData } = supabase.storage.from("chat-images").getPublicUrl(fileName);
    await sendMessage(null, urlData.publicUrl);
  };

});