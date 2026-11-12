import { env } from "cloudflare:workers";
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";

const bindings = { ...env, APP_TOKEN: "test-app-token", ANTHROPIC_API_KEY: "test-provider-key" };
const payload = () => ({ model: "claude-sonnet-5-5", max_tokens: 16000, stream: true, system: "Extract a timetable", messages: [{role: "user", content: [{type: "text", text: "Monday, Math, 8:30-9:20"}]}] });
let ip = 0;
function request(body: unknown = payload(), extra: Record<string,string> = {}) {
  return new Request("https://reader.test/v1/messages", {method: "POST", headers: {"content-type": "application/json", authorization: "Bearer test-app-token", "CF-Connecting-IP": `192.0.2.${++ip}`, ...extra}, body: JSON.stringify(body)});
}
afterEach(() => vi.unstubAllGlobals());

it("serves public policy and support without credentials", async () => {
  const r = await worker.fetch(new Request("https://reader.test/privacy"), bindings);
  expect(r.status).toBe(200);
  expect(await r.text()).toContain("yukifpv1250@gmail.com");
  expect(r.headers.get("content-security-policy")).toContain("frame-ancestors 'none'");
});
it("rejects wrong credentials without calling the provider", async () => {
  const upstream = vi.fn(); vi.stubGlobal("fetch", upstream);
  expect((await worker.fetch(request(undefined, {authorization: "Bearer wrong"}), bindings)).status).toBe(401);
  expect(upstream).not.toHaveBeenCalled();
});
it.each([
  { ...payload(), model: "another-expensive-model" },
  { ...payload(), max_tokens: 16001 },
  { ...payload(), tools: [{ type: "web_search" }] },
  { ...payload(), messages: [{role: "assistant", content: []}] },
  { ...payload(), messages: [{role: "user", content: [{type: "document", source: {type: "url", url: "https://example.com"}}]}] },
])("rejects arbitrary model, spending overrides, tools, and remote documents", async body => {
  const upstream = vi.fn(); vi.stubGlobal("fetch", upstream);
  expect((await worker.fetch(request(body), bindings)).status).toBe(400);
  expect(upstream).not.toHaveBeenCalled();
});
it("enforces actual bytes when Content-Length is missing", async () => {
  const upstream = vi.fn(); vi.stubGlobal("fetch", upstream);
  let chunks = 0;
  const body = new ReadableStream({pull(c) { if (chunks++ < 9) c.enqueue(new Uint8Array(1024*1024)); else c.close(); }});
  const r = new Request("https://reader.test/v1/messages", {method: "POST", headers: {"content-type":"application/json", authorization:"Bearer test-app-token", "CF-Connecting-IP":`192.0.2.${++ip}`}, body});
  expect((await worker.fetch(r,bindings)).status).toBe(413);
  expect(upstream).not.toHaveBeenCalled();
});
it("blocks oversized token input before paid inference", async () => {
  const upstream=vi.fn().mockResolvedValue(Response.json({input_tokens:20001}));vi.stubGlobal("fetch",upstream);
  expect((await worker.fetch(request(),bindings)).status).toBe(413);
  expect(upstream).toHaveBeenCalledTimes(1);
  expect(String(upstream.mock.calls[0][0])).toMatch(/\/count_tokens$/);
});
it("fails closed if token counting fails", async () => {
  const upstream=vi.fn().mockRejectedValue(new Error("offline"));vi.stubGlobal("fetch",upstream);
  expect((await worker.fetch(request(),bindings)).status).toBe(502);
  expect(upstream).toHaveBeenCalledTimes(1);
});
it("streams successful responses and pins provider credentials/version", async () => {
  const upstream=vi.fn().mockResolvedValueOnce(Response.json({input_tokens:100})).mockResolvedValueOnce(new Response("data: test\n\n",{headers:{"content-type":"text/event-stream"}}));vi.stubGlobal("fetch",upstream);
  const r=await worker.fetch(request(),bindings);
  expect(r.status).toBe(200);expect(await r.text()).toBe("data: test\n\n");
  expect(r.headers.get("cache-control")).toBe("no-store");
  expect(upstream.mock.calls[1][1].headers["anthropic-version"]).toBe("2023-06-01");
  expect(upstream.mock.calls[1][1].headers["x-api-key"]).toBe("test-provider-key");
});
describe("durable spending quota", () => {
  it("permits exactly the limit under concurrent requests and survives eviction", async () => {
    const stub=env.READER_QUOTA.getByName(crypto.randomUUID());
    const result=await Promise.all(Array.from({length:30},()=>stub.consume(3)));
    expect(result.filter(Boolean)).toHaveLength(3);
    await evictDurableObject(stub);
    expect(await stub.consume(3)).toBe(false);
    const persisted=await runInDurableObject(stub,(_obj,state)=>state.storage.sql.exec("SELECT used FROM quota").one());
    expect(persisted.used).toBe(3);
  });
  it("keeps quota identities separate and deletes expired state", async () => {
    const a=env.READER_QUOTA.getByName(crypto.randomUUID()),b=env.READER_QUOTA.getByName(crypto.randomUUID());
    expect(await a.consume(1)).toBe(true);expect(await a.consume(1)).toBe(false);expect(await b.consume(1)).toBe(true);
    expect(await runDurableObjectAlarm(a)).toBe(true);
    expect(await runInDurableObject(a,(_obj,state)=>state.storage.list())).toEqual(new Map());
  });
});
