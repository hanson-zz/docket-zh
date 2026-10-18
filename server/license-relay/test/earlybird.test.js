// npm test 或 node --test test/*.test.js  （不需要装任何依赖）
import test from "node:test";
import assert from "node:assert/strict";
import worker, { countEarlybird, countsAsSale } from "../worker.js";

const P = "prod_XYf9P2X55fvYZQOLhs3Lr";
const tx = (o) => ({ id: "tran_" + Math.random(), mode: "prod", object: "transaction", type: "payment", status: "paid",
  amount: 690, amount_paid: 690, currency: "USD", product: P, order: "ord_" + Math.random(), customer: "cust_x", ...o });

function fakeCreem(pages) {
  const calls = [];
  const f = async (url, init) => {
    calls.push({ url, init });
    const page = Number(new URL(url).searchParams.get("page_number"));
    const items = pages[page - 1] || [];
    return new Response(JSON.stringify({ items, pagination: { total_records: 0, total_pages: pages.length, current_page: page,
      next_page: page < pages.length ? page + 1 : null, prev_page: null } }), { status: 200 });
  };
  f.calls = calls;
  return f;
}

test("只数已付款、正式环境、实付大于 0 的一次性付款，同一订单只算一次", async () => {
  const dup = tx({ order: "ord_dup" });
  const f = fakeCreem([[tx(), tx({ status: "partialRefund" }), tx({ status: "refunded" }), tx({ status: "chargedBack" }),
    tx({ status: "pending" }), tx({ mode: "test" }), tx({ amount_paid: 0 }), tx({ type: "invoice" }), dup],
    [{ ...dup, id: "tran_again" }, tx({ order: "ord_mine" }), tx({ product: "prod_632G8EgQJWLL6m9M5JaBXv" })]]);
  const r = await countEarlybird({ CREEM_API_KEY: "k", EARLYBIRD_EXCLUDE: "ord_mine" }, f);
  assert.deepEqual(r, { total: 20, sold: 3, remaining: 17, soldOut: false });
  assert.equal(f.calls.length, 2);
  assert.match(f.calls[0].url, /\/v1\/transactions\/search\?product_id=prod_XYf9P2X55fvYZQOLhs3Lr&page_number=1/);
  assert.equal(f.calls[0].init.headers["x-api-key"], "k");
});

test("卖满 20 份就 soldOut，超卖也不出现负数", async () => {
  const f = fakeCreem([Array.from({ length: 23 }, () => tx())]);
  assert.deepEqual(await countEarlybird({ CREEM_API_KEY: "k" }, f), { total: 20, sold: 20, remaining: 0, soldOut: true });
});

test("测试环境只数 test 交易", async () => {
  assert.equal(countsAsSale(tx({ mode: "test" }), { products: [P], mode: "test", exclude: [] }), true);
  assert.equal(countsAsSale(tx(), { products: [P], mode: "test", exclude: [] }), false);
});

test("接口只回数字，CORS 只放官网", async () => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = fakeCreem([[tx({ customer: "cust_secret", order: "ord_secret" })]]);
  try {
    const res = await worker.fetch(new Request("https://w.dev/earlybird", { headers: { origin: "https://docket.shiduo.app" } }), { CREEM_API_KEY: "k" }, {});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("access-control-allow-origin"), "https://docket.shiduo.app");
    assert.match(res.headers.get("cache-control"), /max-age=60/);
    const text = await res.text();
    assert.doesNotMatch(text, /cust_|ord_|secret|@/);
    const body = JSON.parse(text);
    assert.deepEqual(Object.keys(body).sort(), ["remaining", "sold", "soldOut", "total", "updatedAt"]);
    assert.equal(body.remaining, 19);
    const evil = await worker.fetch(new Request("https://w.dev/earlybird", { headers: { origin: "https://evil.example" } }), { CREEM_API_KEY: "k" }, {});
    assert.equal(evil.headers.get("access-control-allow-origin"), null);
    const pre = await worker.fetch(new Request("https://w.dev/earlybird", { method: "OPTIONS", headers: { origin: "https://docket.shiduo.app" } }), {}, {});
    assert.equal(pre.status, 204);
  } finally { globalThis.fetch = realFetch; }
});

test("Creem 出错时回 502，不缓存", async () => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("{}", { status: 403 });
  try {
    const res = await worker.fetch(new Request("https://w.dev/earlybird"), { CREEM_API_KEY: "k" }, {});
    assert.equal(res.status, 502);
    assert.equal(res.headers.get("cache-control"), "no-store");
  } finally { globalThis.fetch = realFetch; }
});

test("健康检查不受影响", async () => {
  const res = await worker.fetch(new Request("https://w.dev/"), {}, {});
  assert.deepEqual(await res.json(), { ok: true, service: "dockling-license" });
});
