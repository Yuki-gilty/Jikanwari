import { DurableObject } from "cloudflare:workers";
import privacy from "./privacy.html";
import support from "./support.html";

// Secrets live only in Worker bindings. APP_TOKEN is an app identifier, not proof of device authenticity.
interface Secrets { ANTHROPIC_API_KEY: string; APP_TOKEN: string }
type ReaderEnv = Env & Secrets;
const UPSTREAM = "https://api.anthropic.com/v1/messages";
const MAX_BODY = 8 * 1024 * 1024;
const MODEL = "claude-sonnet-5-5";

// A counter per UTC day and quota scope; never stores uploaded documents or raw IP addresses.
export class ReaderQuota extends DurableObject {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS quota (id INTEGER PRIMARY KEY, used INTEGER NOT NULL)");
  }
  async consume(limit: number): Promise<boolean> {
    const rows = this.ctx.storage.sql.exec<{ used: number }>(
      "INSERT INTO quota (id, used) VALUES (1, 1) ON CONFLICT(id) DO UPDATE SET used = used + 1 WHERE used < ? RETURNING used", limit,
    ).toArray();
    if (await this.ctx.storage.getAlarm() === null) await this.ctx.storage.setAlarm(Date.now() + 2 * 86400000);
    return rows.length === 1;
  }
  async alarm(): Promise<void> { await this.ctx.storage.deleteAll(); }
}

export default {
  async fetch(req: Request, env: ReaderEnv): Promise<Response> {
    const url = new URL(req.url);
    if (req.method === "GET" && ["/privacy", "/support", "/"].includes(url.pathname)) {
      return new Response(url.pathname === "/privacy" ? privacy : support, { headers: {
        "content-type": "text/html; charset=utf-8", "x-content-type-options": "nosniff",
        "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
        "referrer-policy": "no-referrer",
      }});
    }
    if (req.method !== "POST" || url.pathname !== "/v1/messages") return error(404, "not_found_error", "not found");
    if (!env.APP_TOKEN || !env.ANTHROPIC_API_KEY) return error(503, "api_error", "読み取りを一時的に利用できません");
    if (!(await same(req.headers.get("authorization") ?? "", `Bearer ${env.APP_TOKEN}`))) return error(401, "authentication_error", "認証に失敗しました");
    if (req.headers.get("content-type")?.split(";")[0].trim() !== "application/json") return error(415, "invalid_request_error", "JSONが必要です");
    const length = req.headers.get("content-length");
    if (length && (!/^\d+$/.test(length) || Number(length) > MAX_BODY)) return error(413, "request_too_large", "ファイルが大きすぎます");
    // Cloudflare supplies this header; clients cannot select the quota key.
    const ip = req.headers.get("CF-Connecting-IP");
    if (!ip) return error(503, "api_error", "読み取りを一時的に利用できません");
    const day = new Date().toISOString().slice(0, 10);
    const client = await digest(`${env.APP_TOKEN}:${day}:${ip}`);
    const burst = await env.READER_RATE_LIMIT.limit({ key: client });
    if (!burst.success) return error(429, "rate_limit_error", "少し待ってからもう一度お試しください");
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(await boundedText(req));
    } catch (e) {
      return error(e instanceof RangeError ? 413 : 400, "invalid_request_error", e instanceof RangeError ? "ファイルが大きすぎます" : "リクエストを読み取れません");
    }
    if (!valid(body)) return error(400, "invalid_request_error", "時間割の読み取りに対応していないリクエストです");
    // Reserve before the upstream call, including failures: retries cannot bypass the spending bound.
    if (!(await env.READER_QUOTA.getByName(`${day}:client:${client}`).consume(10))) return error(429, "rate_limit_error", "本日の読み取り回数の上限に達しました");
    if (!(await env.READER_QUOTA.getByName(`${day}:global`).consume(100))) return error(429, "rate_limit_error", "本日の読み取りサービスの上限に達しました。明日もう一度お試しください");
    try {
      const countResponse = await fetch(`${UPSTREAM}/count_tokens`, {
        method: "POST", headers: { "content-type": "application/json", "anthropic-version": "2023-06-01", "x-api-key": env.ANTHROPIC_API_KEY },
        body: JSON.stringify({ model: MODEL, system: body.system, messages: body.messages }), signal: AbortSignal.timeout(30000),
      });
      if (!countResponse.ok) {
        await countResponse.body?.cancel();
        return error(502, "api_error", "資料の大きさを確認できませんでした。少し待ってからお試しください");
      }
      const count = await countResponse.json<{ input_tokens: number }>();
      if (!Number.isSafeInteger(count.input_tokens) || count.input_tokens < 1) return error(502, "api_error", "資料の大きさを確認できませんでした");
      if (count.input_tokens > 20000) return error(413, "request_too_large", "資料が長すぎます。自分のクラスのページだけを選んでください");
      const upstream = await fetch(UPSTREAM, {
        method: "POST", headers: { "content-type": "application/json", "anthropic-version": "2023-06-01", "x-api-key": env.ANTHROPIC_API_KEY },
        body: JSON.stringify(body), signal: AbortSignal.timeout(280000),
      });
      if (!upstream.ok) {
        await upstream.body?.cancel();
        return error(upstream.status === 429 || upstream.status === 529 ? 429 : 502, "api_error", "読み取りサービスを利用できません。少し待ってからお試しください");
      }
      return new Response(upstream.body, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/json", "cache-control": "no-store", "x-content-type-options": "nosniff" }});
    } catch {
      return error(502, "api_error", "読み取りサービスに接続できません。少し待ってからお試しください");
    }
  },
} satisfies ExportedHandler<ReaderEnv>;

function valid(b: Record<string, unknown>): boolean {
  if (!b || typeof b !== "object" || Array.isArray(b)) return false;
  if (Object.keys(b).some(k => !["model", "max_tokens", "stream", "system", "output_config", "messages"].includes(k))) return false;
  if (b.model !== MODEL || b.stream !== true || !Number.isInteger(b.max_tokens) || Number(b.max_tokens) < 1 || Number(b.max_tokens) > 16000) return false;
  if (typeof b.system !== "string" || b.system.length > 16000) return false;
  if (b.output_config !== undefined) {
    const output = b.output_config as Record<string, unknown>;
    if (!output || typeof output !== "object" || JSON.stringify(output).length > 12000) return false;
    if (Object.keys(output).some(k => !["effort", "format"].includes(k))) return false;
    if (output.effort !== "high") return false;
    const format = output.format as Record<string, unknown> | undefined;
    if (!format || format.type !== "json_schema" || !format.schema || typeof format.schema !== "object") return false;
  }
  if (!Array.isArray(b.messages) || b.messages.length !== 1) return false;
  const message = b.messages[0];
  if (!message || message.role !== "user" || !Array.isArray(message.content) || message.content.length < 1 || message.content.length > 11) return false;
  return message.content.every((c: unknown) => {
    if (!c || typeof c !== "object") return false;
    const block = c as Record<string, unknown>;
    if (block.type === "text") return typeof block.text === "string" && block.text.length <= 16000;
    if (block.type !== "image" && block.type !== "document") return false;
    const source = block.source as Record<string, unknown> | undefined;
    if (!source || typeof source.data !== "string") return false;
    if (block.type === "image") return source.type === "base64" && source.media_type === "image/jpeg";
    return (source.type === "base64" && source.media_type === "application/pdf") || (source.type === "text" && source.media_type === "text/plain");
  });
}
async function boundedText(req: Request): Promise<string> {
  if (!req.body) throw new Error("missing body");
  const reader = req.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false });
  let size = 0, text = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY) { await reader.cancel(); throw new RangeError("body limit"); }
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } finally { reader.releaseLock(); }
}
function error(status: number, type: string, message: string): Response {
  return Response.json({ type: "error", error: { type, message } }, { status, headers: { "cache-control": "no-store", ...(status === 429 ? { "retry-after": "60" } : {}) } });
}
async function digest(value: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))), b => b.toString(16).padStart(2, "0")).join("");
}
async function same(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([crypto.subtle.digest("SHA-256", enc.encode(a)), crypto.subtle.digest("SHA-256", enc.encode(b))]);
  return crypto.subtle.timingSafeEqual(ha, hb);
}
