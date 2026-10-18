// 码头 Pro 授权中转（Cloudflare Worker），做法与兄弟应用拾掇的中转一致。
// App 不能内置 Creem 的 API 密钥（代码是公开的），所以由这个小服务代为调用 Creem。
// 只转发三件事：激活、校验、解绑；并且只认码头 Pro 这个产品的授权码，拾掇或别的产品的码一律当作不存在。
//
// 需要在 Cloudflare 里设置：
//   CREEM_API_KEY  （Secret）Creem 后台 ▸ Developers ▸ API Keys
//   PRODUCT_ID     （变量）Creem 里码头 Pro 产品的 ID，形如 prod_xxx；多个用英文逗号隔开。
//                  没填时用下面写死的 DEFAULT_PRODUCT_ID，绝不会放行任意产品。
//   CREEM_API      （变量，可选）测试时填 https://test-api.creem.io
//   ADMIN_TOKEN    （Secret）兑换码管理页的密码，自己定
//   GIFTS          （KV 绑定）存兑换码
//   EARLYBIRD_TOTAL   （变量，可选）首批限量份数，默认 20
//   EARLYBIRD_EXCLUDE （变量，可选）不算进首批的 Creem 订单号，英文逗号隔开（比如自己下的测试单）
//
// 返回给 App 的格式（与 App 里 ProLicenseResponse.parse 对应）：
//   { activated|valid|deactivated: Bool, error?: String,
//     instance: { id }, license_key: { status }, meta: { product_id } }

// 码头 Pro 的 Creem 产品 ID。PRODUCT_ID 变量没设时用它，保证只认码头的码。
const DEFAULT_PRODUCT_ID = "prod_XYf9P2X55fvYZQOLhs3Lr";

// 兑换码记录里标明属于哪个应用，万一和拾掇共用了同一个 KV 也不会串。
const GIFT_PRODUCT = "dockling";

function allowedProducts(env) {
  const list = String(env.PRODUCT_ID || "").split(",").map(s => s.trim()).filter(Boolean);
  return list.length ? list : [DEFAULT_PRODUCT_ID];
}

const ACTIONS = { activate: "activated", validate: "valid", deactivate: "deactivated" };

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

// ---------- 兑换码（送朋友 / 粉丝） ----------
// 兑换码形如 DKG-XXXX-XXXX-XXXX，存在 KV（绑定名 GIFTS）里，每个码只能同时激活一台 Mac，
// 解绑后可以换到另一台。管理页：打开 <Worker 地址>/admin，输入 ADMIN_TOKEN 生成 / 查看 / 作废。

const ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"; // 去掉了 0 O 1 I 等容易看错的字符

function newGiftCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  const chars = Array.from(bytes, b => ALPHABET[b % 32]).join("");
  return `DKG-${chars.slice(0, 4)}-${chars.slice(4, 8)}-${chars.slice(8, 12)}`;
}

function isGift(key) {
  return /^DKG-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}-[2-9A-HJ-NP-Z]{4}$/.test(key);
}

async function handleGift(action, flag, key, input, env) {
  if (!env.GIFTS) return json({ error: "gift codes not configured" }, 502);
  const raw = await env.GIFTS.get("gift:" + key);
  if (!raw) return json({ [flag]: false, error: "license_key not found." }, 404);
  const rec = JSON.parse(raw);
  // 不是码头的兑换码（比如别的应用写进同一个 KV 的）：当作不存在。
  if (rec.product && rec.product !== GIFT_PRODUCT) return json({ [flag]: false, error: "license_key not found." }, 404);
  const meta = { product_id: allowedProducts(env)[0] };
  if (rec.status === "revoked") {
    return json({ [flag]: false, error: "license disabled", license_key: { status: "disabled" }, meta });
  }
  if (action === "activate") {
    if (rec.instance_id) return json({ activated: false, error: "activation limit reached" }, 400);
    rec.instance_id = "gift_inst_" + crypto.randomUUID();
    rec.instance_name = String(input.instance_name || "Mac").slice(0, 100);
    rec.activated_at = new Date().toISOString();
    await env.GIFTS.put("gift:" + key, JSON.stringify(rec));
    return json({ activated: true, instance: { id: rec.instance_id }, license_key: { status: "active" }, meta });
  }
  const same = rec.instance_id && rec.instance_id === String(input.instance_id || "");
  if (action === "validate") {
    return json({ valid: !!same, error: same ? undefined : "instance not found.", instance: same ? { id: rec.instance_id } : undefined,
      license_key: { status: rec.instance_id ? "active" : "inactive" }, meta });
  }
  // deactivate
  if (!same) return json({ deactivated: false, error: "instance not found." }, 404);
  delete rec.instance_id; delete rec.instance_name; delete rec.activated_at;
  await env.GIFTS.put("gift:" + key, JSON.stringify(rec));
  return json({ deactivated: true, license_key: { status: "inactive" }, meta });
}

const ADMIN_HTML = `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>码头 Pro 兑换码</title>
<style>body{font:15px -apple-system,system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 16px;color:#222}
input,select,button{font:inherit;padding:8px 10px;margin:4px 0;border:1px solid #ccc;border-radius:8px}button{background:#2f6fed;color:#fff;border:0;cursor:pointer}
textarea{width:100%;height:260px;font:13px ui-monospace,monospace;border-radius:8px;border:1px solid #ccc;padding:8px}label{display:block;margin-top:10px}</style>
<h2>码头 Pro 兑换码</h2>
<label>管理密码 <input id="t" type="password" placeholder="ADMIN_TOKEN"></label>
<label>数量 <input id="n" type="number" value="5" min="1" max="200"></label>
<label>备注（送给谁） <input id="note" placeholder="例如：小红书粉丝抽奖"></label>
<p><button onclick="go('new')">生成兑换码</button> <button onclick="go('list')">查看全部</button></p>
<label>作废某个码 <input id="code" placeholder="DKG-XXXX-XXXX-XXXX"> <button onclick="go('revoke')">作废</button></label>
<textarea id="out" readonly></textarea>
<script>
async function go(a){const r=await fetch('/admin/'+a,{method:'POST',headers:{'content-type':'application/json'},
body:JSON.stringify({token:t.value,count:+n.value,note:note.value,code:code.value.trim().toUpperCase()})});out.value=await r.text();}
</script></html>`;

async function handleAdmin(path, request, env) {
  if (request.method === "GET" && path === "/admin") {
    return new Response(ADMIN_HTML, { headers: { "content-type": "text/html; charset=utf-8" } });
  }
  if (request.method !== "POST") return json({ error: "not found" }, 404);
  let input = {};
  try { input = await request.json(); } catch {}
  if (!env.ADMIN_TOKEN || String(input.token || "") !== env.ADMIN_TOKEN) {
    return new Response("管理密码不对。", { status: 401 });
  }
  if (!env.GIFTS) return new Response("还没有绑定 KV（变量名 GIFTS）。", { status: 500 });
  const text = (s, status = 200) => new Response(s, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
  if (path === "/admin/new") {
    const count = Math.min(200, Math.max(1, parseInt(input.count, 10) || 1));
    const note = String(input.note || "").slice(0, 100);
    const codes = [];
    for (let i = 0; i < count; i++) {
      const code = newGiftCode();
      await env.GIFTS.put("gift:" + code, JSON.stringify({ status: "ok", product: GIFT_PRODUCT, note, created_at: new Date().toISOString() }));
      codes.push(code);
    }
    return text(codes.join("\n"));
  }
  if (path === "/admin/list") {
    const lines = [];
    let cursor;
    do {
      const page = await env.GIFTS.list({ prefix: "gift:", cursor });
      for (const k of page.keys) {
        const rec = JSON.parse((await env.GIFTS.get(k.name)) || "{}");
        const state = rec.status === "revoked" ? "已作废" : rec.instance_id ? `已激活（${rec.instance_name || "Mac"}）` : "未使用";
        lines.push(`${k.name.slice(5)}\t${state}\t${rec.note || ""}`);
      }
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
    return text(lines.length ? lines.join("\n") : "还没有兑换码。");
  }
  if (path === "/admin/revoke") {
    const code = String(input.code || "");
    const raw = await env.GIFTS.get("gift:" + code);
    if (!raw) return text("找不到这个码。", 404);
    const rec = JSON.parse(raw);
    rec.status = "revoked";
    await env.GIFTS.put("gift:" + code, JSON.stringify(rec));
    return text(`${code} 已作废。`);
  }
  return json({ error: "not found" }, 404);
}

// ---------- 首批限量（官网读的公开计数） ----------
// GET /earlybird → { total, sold, remaining, soldOut, updatedAt }
// 数据来自 Creem 的 GET /v1/transactions/search?product_id=…（官方文档：
// https://docs.creem.io/api-reference/endpoint/get-transactions），用的就是上面已有的 CREEM_API_KEY。
// 计数口径：只数码头 Pro 产品的一次性付款（type=payment），状态是 paid 或 partialRefund，
// 实付金额大于 0，环境与当前 API 一致（正式环境只数 prod）。全额退款、拒付、作废、待付都不算；
// DKG- 兑换码不经过 Creem，本来就不在里面。EARLYBIRD_EXCLUDE 变量可填要排除的订单号（自己下的测试单）。
// 只回四个数字，绝不回买家、订单号或金额。结果在 Cloudflare 边缘缓存 60 秒，免得每次打开页面都去问 Creem。

const EARLYBIRD_ORIGINS = ["https://docket.shiduo.app", "https://hanson-zz.github.io"];
const EARLYBIRD_TTL = 60;
const COUNTED_STATUS = new Set(["paid", "partialRefund"]);

function earlybirdHeaders(request, extra = {}) {
  const origin = request.headers.get("origin") || "";
  const h = { "content-type": "application/json; charset=utf-8", vary: "Origin", ...extra };
  if (EARLYBIRD_ORIGINS.includes(origin)) {
    h["access-control-allow-origin"] = origin;
    h["access-control-allow-methods"] = "GET, OPTIONS";
    h["access-control-max-age"] = "86400";
  }
  return h;
}

// 只看一笔交易该不该算进首批，单独拿出来方便测试。
export function countsAsSale(t, { products, mode, exclude }) {
  if (!t || t.type !== "payment") return false;
  if (!COUNTED_STATUS.has(t.status)) return false;
  if (mode && t.mode && t.mode !== mode) return false;
  if (t.product && !products.includes(t.product)) return false;
  const paid = t.amount_paid ?? t.amount;
  if (!(Number(paid) > 0)) return false;
  if (t.order && exclude.includes(t.order)) return false;
  return true;
}

export async function countEarlybird(env, fetchImpl = fetch) {
  const base = env.CREEM_API || "https://api.creem.io";
  const mode = base.includes("test-api") ? "test" : "prod";
  const products = allowedProducts(env);
  const exclude = String(env.EARLYBIRD_EXCLUDE || "").split(",").map(s => s.trim()).filter(Boolean);
  const total = Math.max(0, parseInt(env.EARLYBIRD_TOTAL, 10) || 20);
  const seen = new Set();
  let sold = 0;
  for (const product of products) {
    for (let page = 1; page <= 20; page++) {
      const url = `${base}/v1/transactions/search?product_id=${encodeURIComponent(product)}&page_number=${page}&page_size=50`;
      const res = await fetchImpl(url, { headers: { "x-api-key": env.CREEM_API_KEY, accept: "application/json" } });
      if (!res.ok) throw new Error("creem " + res.status);
      const data = await res.json();
      for (const t of data.items || []) {
        if (!countsAsSale(t, { products, mode, exclude })) continue;
        const k = t.order || t.id;
        if (seen.has(k)) continue;
        seen.add(k);
        sold++;
      }
      if (!data.pagination || !data.pagination.next_page) break;
    }
  }
  const remaining = Math.max(0, total - sold);
  return { total, sold: Math.min(sold, total), remaining, soldOut: remaining === 0 };
}

async function handleEarlybird(request, env, ctx) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: earlybirdHeaders(request) });
  const cache = typeof caches !== "undefined" ? caches.default : null;
  const cacheKey = new Request(new URL("/earlybird", request.url).toString(), { method: "GET" });
  let body = null;
  if (cache) {
    const hit = await cache.match(cacheKey);
    if (hit) body = await hit.text();
  }
  if (!body) {
    if (!env.CREEM_API_KEY) return new Response(JSON.stringify({ error: "not configured" }), { status: 503, headers: earlybirdHeaders(request, { "cache-control": "no-store" }) });
    let result;
    try { result = await countEarlybird(env); }
    catch { return new Response(JSON.stringify({ error: "upstream unavailable" }), { status: 502, headers: earlybirdHeaders(request, { "cache-control": "no-store" }) }); }
    body = JSON.stringify({ ...result, updatedAt: new Date().toISOString() });
    if (cache) {
      const put = cache.put(cacheKey, new Response(body, { headers: { "content-type": "application/json", "cache-control": `public, max-age=${EARLYBIRD_TTL}` } }));
      if (ctx && ctx.waitUntil) ctx.waitUntil(put); else await put;
    }
  }
  return new Response(body, { headers: earlybirdHeaders(request, { "cache-control": `public, max-age=${EARLYBIRD_TTL}` }) });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/earlybird" && (request.method === "GET" || request.method === "OPTIONS")) return handleEarlybird(request, env, ctx);
    if (url.pathname === "/admin" || url.pathname.startsWith("/admin/")) return handleAdmin(url.pathname, request, env);
    const match = url.pathname.match(/^\/v1\/licenses\/(activate|validate|deactivate)$/);
    if (request.method === "GET" && url.pathname === "/") return json({ ok: true, service: "dockling-license" });
    if (!match || request.method !== "POST") return json({ error: "not found" }, 404);
    const action = match[1];
    const flag = ACTIONS[action];

    let input;
    try { input = await request.json(); } catch { return json({ [flag]: false, error: "invalid request" }, 400); }
    const key = String(input.key || "").trim();
    if (!key || key.length > 200) return json({ [flag]: false, error: "license_key not found." }, 404);

    if (isGift(key.toUpperCase())) return handleGift(action, flag, key.toUpperCase(), input, env);

    const payload = { key };
    if (action === "activate") payload.instance_name = String(input.instance_name || "Mac").slice(0, 100);
    else {
      const id = String(input.instance_id || "");
      if (!id) return json({ [flag]: false, error: "instance not found." }, 404);
      payload.instance_id = id;
    }

    const base = env.CREEM_API || "https://api.creem.io";
    let res, data;
    try {
      res = await fetch(`${base}/v1/licenses/${action}`, {
        method: "POST",
        headers: { "x-api-key": env.CREEM_API_KEY, "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify(payload),
      });
      data = await res.json();
    } catch {
      return json({ error: "upstream unavailable" }, 502);
    }

    if (!res.ok) {
      const msg = Array.isArray(data?.message) ? data.message.join(" ") : (data?.message || data?.error || "");
      const low = String(msg).toLowerCase();
      let error = "license error";
      if (res.status === 404 || low.includes("not found")) error = action === "activate" ? "license_key not found." : "instance not found.";
      else if (low.includes("limit")) error = "activation limit reached";
      else if (low.includes("expired")) error = "license expired";
      else if (low.includes("disabled")) error = "license disabled";
      else if (res.status === 429) error = "too many requests";
      else if (res.status === 401 || res.status === 403) return json({ error: "server misconfigured" }, 502);
      // 校验时授权已失效：告诉 App 明确不可用
      return json({ [flag]: false, error }, res.status === 429 ? 429 : 400);
    }

    const allowed = allowedProducts(env);
    if (!data.product_id || !allowed.includes(data.product_id)) {
      // 不是码头 Pro 的授权码（例如拾掇的）；激活时把刚占用的名额还回去
      if (action === "activate" && data.instance?.id) {
        await fetch(`${base}/v1/licenses/deactivate`, {
          method: "POST",
          headers: { "x-api-key": env.CREEM_API_KEY, "content-type": "application/json" },
          body: JSON.stringify({ key, instance_id: data.instance.id }),
        }).catch(() => {});
      }
      return json({ [flag]: false, error: "license_key not found." }, 404);
    }

    const instanceActive = !data.instance || data.instance.status !== "deactivated";
    const statusOK = data.status === "active" || data.status === "inactive";
    let ok = true;
    if (action === "validate") ok = statusOK && instanceActive;
    if (action === "activate") ok = statusOK && !!data.instance?.id;
    return json({
      [flag]: ok,
      error: ok ? undefined : (data.status === "expired" ? "license expired" : data.status === "disabled" ? "license disabled" : "instance not found."),
      instance: data.instance ? { id: data.instance.id } : undefined,
      license_key: { status: data.status },
      meta: { product_id: data.product_id },
    });
  },
};
