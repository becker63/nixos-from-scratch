import { z } from "zod/v4";
const description = z.string().min(1).max(2000);
const question = z.discriminatedUnion("type", [
  z
    .object({
      type: z.literal("noul"),
      instructions: description,
      criteria: z
        .object({ true: description.optional(), false: description.optional() })
        .strict()
        .optional(),
    })
    .strict(),
  z
    .object({
      type: z.literal("choice"),
      instructions: description,
      criteria: z
        .record(z.string().regex(/^[a-z][a-z0-9_]{0,63}$/), description)
        .refine(
          (c) => Object.keys(c).length >= 2 && Object.keys(c).length <= 16,
        ),
    })
    .strict(),
  z
    .object({
      type: z.literal("score"),
      instructions: description,
      criteria: z.array(description).min(2).max(10),
    })
    .strict(),
]);
export const requestSchema = z
  .object({
    scope: z.string().min(1).max(100).optional(),
    state: z.string().min(1).max(24000),
    questions: z
      .record(z.string().regex(/^[a-z][a-z0-9_]{0,63}$/), question)
      .refine((q) => Object.keys(q).length >= 1 && Object.keys(q).length <= 8),
  })
  .strict();
export type Question = z.infer<typeof question>;
export type JudgeRequest = z.infer<typeof requestSchema>;
export type Answer =
  | { type: "noul"; probability: number }
  | {
      type: "choice";
      choice: string;
      confidence: number;
      probabilities: Record<string, number>;
    }
  | {
      type: "score";
      score: number;
      confidence: number;
      probabilities: Record<string, number>;
      legend: Record<string, string>;
    };
export type DecisionResult =
  | {
      ok: true;
      model: string;
      answers: Record<string, Answer>;
      usage: { input_tokens: number; output_tokens: number; cost?: number };
      wallMs: number;
    }
  | {
      ok: false;
      status: "provider_failure";
      reason:
        | "invalid_request"
        | "missing_key"
        | "http"
        | "transport"
        | "malformed_response"
        | "budget";
      httpStatus?: number;
      errorCode?:
        | "service_overloaded"
        | "rate_limited"
        | "overloaded"
        | "unauthorized";
      retryAfterSeconds?: number;
      wallMs: number;
    };
export interface DecisionProvider {
  judge(request: JudgeRequest): Promise<DecisionResult>;
}
export const SYSTEM_ONE_MODEL = "morph-systemone-v1";
const probability = z.number().finite().min(0).max(1);
const wireAnswer = z.discriminatedUnion("type", [
  z.object({ type: z.literal("noul"), noul: probability }).strict(),
  z
    .object({
      type: z.literal("choice"),
      choice: z.string(),
      confidence: probability,
      probabilities: z.record(z.string(), probability),
    })
    .strict(),
  z
    .object({
      type: z.literal("score"),
      score: z.number().finite(),
      confidence: probability,
      probabilities: z.record(z.string(), probability),
      legend: z.record(z.string(), z.string()),
    })
    .strict(),
]);
const envelope = z
  .object({
    model: z.string().min(1),
    answers: z.record(z.string(), wireAnswer),
    usage: z
      .object({
        input_tokens: z.number().int().nonnegative(),
        output_tokens: z.number().int().nonnegative(),
        cost: z.number().finite().nonnegative().optional(),
      })
      .passthrough(),
  })
  .passthrough();
function sameKeys(a: object, keys: string[]) {
  return (
    JSON.stringify(Object.keys(a).sort()) === JSON.stringify([...keys].sort())
  );
}
/** Validate against the questions actually sent, including winning label and score expectation. */
export function decodeResponse(
  raw: unknown,
  request: JudgeRequest,
  wallMs = 0,
  allowedModel: RegExp = /^morph-systemone-v1$/,
): DecisionResult {
  const parsed = envelope.safeParse(raw);
  if (
    !parsed.success ||
    !allowedModel.test(parsed.data.model) ||
    !sameKeys(parsed.data.answers, Object.keys(request.questions))
  )
    return failure("malformed_response", wallMs);
  const answers: Record<string, Answer> = {};
  for (const [id, q] of Object.entries(request.questions)) {
    const a = parsed.data.answers[id];
    if (a.type !== q.type) return failure("malformed_response", wallMs);
    if (a.type === "noul") {
      answers[id] = { type: "noul", probability: a.noul };
      continue;
    }
    const keys =
      q.type === "choice"
        ? Object.keys(q.criteria)
        : q.type === "score"
          ? q.criteria.map((_, i) => String(i))
          : [];
    const p = a.probabilities;
    if (
      !sameKeys(p, keys) ||
      Math.abs(Object.values(p).reduce((s, n) => s + n, 0) - 1) > 0.02
    )
      return failure("malformed_response", wallMs);
    if (a.type === "choice") {
      if (
        !keys.includes(a.choice) ||
        p[a.choice] < Math.max(...Object.values(p)) - 1e-6
      )
        return failure("malformed_response", wallMs);
      answers[id] = a;
    } else {
      const expected = keys.reduce((s, k, i) => s + i * p[k], 0);
      if (
        q.type !== "score" ||
        a.score < 0 ||
        a.score > keys.length - 1 ||
        Math.abs(a.score - expected) > 0.05 ||
        !sameKeys(a.legend, keys) ||
        keys.some((k, i) => a.legend[k] !== q.criteria[i])
      )
        return failure("malformed_response", wallMs);
      answers[id] = a;
    }
  }
  return {
    ok: true,
    model: parsed.data.model,
    answers,
    usage: parsed.data.usage,
    wallMs,
  };
}
export function failure(
  reason: Extract<DecisionResult, { ok: false }>["reason"],
  wallMs = 0,
  httpStatus?: number,
): DecisionResult {
  return {
    ok: false,
    status: "provider_failure",
    reason,
    wallMs,
    ...(httpStatus === undefined ? {} : { httpStatus }),
  };
}
class HttpDecisionProvider implements DecisionProvider {
  constructor(
    private readonly key: string | undefined,
    private readonly fetcher: typeof fetch,
    private readonly endpoint: string,
    private readonly model: string,
    private readonly allowedModel: RegExp,
  ) {}
  async judge(input: JudgeRequest): Promise<DecisionResult> {
    const start = performance.now(),
      parsed = requestSchema.safeParse(input);
    if (!parsed.success) return failure("invalid_request");
    if (!this.key) return failure("missing_key");
    const { scope: _, ...request } = parsed.data;
    let response: Response;
    try {
      // Fixed provider origin, no redirects, no key in argv or provider error text.
      response = await this.fetcher(this.endpoint, {
        method: "POST",
        redirect: "error",
        headers: {
          Authorization: `Bearer ${this.key}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ model: this.model, ...request }),
        signal: AbortSignal.timeout(15000),
      });
    } catch {
      return failure("transport", Math.round(performance.now() - start));
    }
    const wallMs = Math.round(performance.now() - start);
    if (!response.ok) {
      const result = failure("http", wallMs, response.status);
      if (result.ok) return result;
      const retryAfter = response.headers.get("retry-after");
      if (retryAfter && /^\d{1,4}$/.test(retryAfter)) {
        const seconds = Number(retryAfter);
        if (seconds <= 3600) result.retryAfterSeconds = seconds;
      }
      try {
        const body = await response.text();
        if (body.length <= 8192) {
          const code = JSON.parse(body)?.error?.code;
          // Preserve only known codes; never reflect arbitrary provider text.
          if (
            [
              "service_overloaded",
              "rate_limited",
              "overloaded",
              "unauthorized",
            ].includes(code)
          )
            result.errorCode = code;
        }
      } catch {
        /* HTTP failure remains explicit even when its body is malformed. */
      }
      return result;
    }
    try {
      const body = await response.text();
      if (body.length > 128000) return failure("malformed_response", wallMs);
      return decodeResponse(
        JSON.parse(body),
        parsed.data,
        wallMs,
        this.allowedModel,
      );
    } catch {
      return failure("malformed_response", wallMs);
    }
  }
}
export class MorphSystemOneProvider extends HttpDecisionProvider {
  constructor(key: string | undefined, fetcher: typeof fetch = fetch) {
    super(
      key,
      fetcher,
      "https://api.morphllm.com/v1/singleshot",
      SYSTEM_ONE_MODEL,
      /^morph-systemone-v1$/,
    );
  }
}
export const JEV_MODEL = "typesafe/jev-1.13";
export class OpenRouterJevProvider extends HttpDecisionProvider {
  constructor(key: string | undefined, fetcher: typeof fetch = fetch) {
    super(
      key,
      fetcher,
      "https://openrouter.ai/api/alpha/decisions",
      JEV_MODEL,
      /^typesafe\/jev-1\.13(?:-\d{8})?$/,
    );
  }
}
/** Confidence is distribution concentration, not a calibrated correctness probability. */
export function decisive(answer: Answer | undefined): string | undefined {
  if (answer?.type !== "choice") return undefined;
  const p = answer.probabilities[answer.choice];
  const alternative = Math.max(
    0,
    ...Object.entries(answer.probabilities)
      .filter(([k]) => k !== answer.choice)
      .map(([, v]) => v),
  );
  return answer.confidence >= 0.6 && p >= 0.7 && p - alternative >= 0.2
    ? answer.choice
    : undefined;
}
