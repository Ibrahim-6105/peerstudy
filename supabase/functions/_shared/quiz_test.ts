import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import { ApiError } from "./http.ts";
import {
  aiAttemptSequence,
  aiRetryDelayMilliseconds,
  generateQuestionsFromPdf,
  isTransientAiStatus,
  parseAiModels,
} from "./quiz.ts";

Deno.test("normalizes a bounded lightweight model chain", () => {
  assertEquals(
    parseAiModels(
      "models/gemini-3.5-flash-lite",
      " gemini-3.1-flash-lite,gemini-3.1-flash-lite ",
    ),
    ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite"],
  );
  assertEquals(
    aiAttemptSequence(["primary", "fallback-one", "fallback-two"]),
    ["primary", "fallback-one", "fallback-two", "primary"],
  );
  assertEquals(aiAttemptSequence(["primary"]), [
    "primary",
    "primary",
    "primary",
  ]);
});

Deno.test("rejects unsafe or unbounded model configuration", () => {
  assertThrows(
    () => parseAiModels("bad/model", ""),
    ApiError,
    "model list is invalid",
  );
  assertThrows(
    () => parseAiModels("one", "two,three,four"),
    ApiError,
    "model list is invalid",
  );
});

Deno.test("classifies only retryable provider status codes", () => {
  assertEquals(isTransientAiStatus(408), true);
  assertEquals(isTransientAiStatus(429), true);
  assertEquals(isTransientAiStatus(503), true);
  assertEquals(isTransientAiStatus(400), false);
  assertEquals(isTransientAiStatus(403), false);
  assertEquals(isTransientAiStatus(404), false);
});

Deno.test("uses bounded exponential backoff, jitter, and Retry-After", () => {
  assertEquals(aiRetryDelayMilliseconds(1, null, 0), 1_000);
  assertEquals(aiRetryDelayMilliseconds(2, null, 1), 2_250);
  assertEquals(aiRetryDelayMilliseconds(3, "3", 0), 4_000);
  assertEquals(aiRetryDelayMilliseconds(4, "30", 1), 8_000);
});

Deno.test("moves from a transient primary failure to the fallback model", async () => {
  const environmentNames = [
    "AI_API_KEY",
    "AI_MODEL",
    "AI_FALLBACK_MODEL",
    "AI_FALLBACK_MODELS",
    "AI_API_BASE_URL",
    "AI_TIMEOUT_MS",
    "AI_ATTEMPT_TIMEOUT_MS",
  ];
  const previousEnvironment = new Map(
    environmentNames.map((name) => [name, Deno.env.get(name)]),
  );
  const previousFetch = globalThis.fetch;
  const calls: string[] = [];

  try {
    Deno.env.set("AI_API_KEY", "test-key-never-sent");
    Deno.env.set("AI_MODEL", "primary-lite");
    Deno.env.set("AI_FALLBACK_MODEL", "fallback-lite");
    Deno.env.delete("AI_FALLBACK_MODELS");
    Deno.env.set("AI_API_BASE_URL", "https://provider.test/v1beta");
    Deno.env.set("AI_TIMEOUT_MS", "20000");
    Deno.env.set("AI_ATTEMPT_TIMEOUT_MS", "8000");

    globalThis.fetch = (input, init) => {
      const url = input.toString();
      calls.push(url);
      const request = JSON.parse(init?.body?.toString() ?? "{}") as Record<
        string,
        unknown
      >;
      const config = request.generationConfig as Record<string, unknown>;
      assertEquals(config.maxOutputTokens, 4096);
      assertEquals(config.thinkingConfig, { thinkingLevel: "MINIMAL" });

      if (url.includes("primary-lite")) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              error: { status: "UNAVAILABLE", details: [] },
            }),
            { status: 503, headers: { "retry-after": "0.001" } },
          ),
        );
      }
      return Promise.resolve(validQuizResponse());
    };

    const generated = await generateQuestionsFromPdf(
      new TextEncoder().encode("%PDF-1.4 test"),
      "Stable systems",
      "test-request-id",
    );

    assertEquals(generated.model, "fallback-lite");
    assertEquals(generated.questions.length, 10);
    assertEquals(calls.length, 2);
    assertEquals(calls[0].includes("primary-lite"), true);
    assertEquals(calls[1].includes("fallback-lite"), true);
  } finally {
    globalThis.fetch = previousFetch;
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});

Deno.test("a stalled primary attempt times out and still reaches fallback", async () => {
  const environmentNames = [
    "AI_API_KEY",
    "AI_MODEL",
    "AI_FALLBACK_MODEL",
    "AI_FALLBACK_MODELS",
    "AI_API_BASE_URL",
    "AI_TIMEOUT_MS",
    "AI_ATTEMPT_TIMEOUT_MS",
  ];
  const previousEnvironment = new Map(
    environmentNames.map((name) => [name, Deno.env.get(name)]),
  );
  const previousFetch = globalThis.fetch;
  const calls: string[] = [];

  try {
    Deno.env.set("AI_API_KEY", "test-key-never-sent");
    Deno.env.set("AI_MODEL", "stalled-primary");
    Deno.env.set("AI_FALLBACK_MODEL", "responsive-fallback");
    Deno.env.delete("AI_FALLBACK_MODELS");
    Deno.env.set("AI_API_BASE_URL", "https://provider.test/v1beta");
    Deno.env.set("AI_TIMEOUT_MS", "20000");
    Deno.env.set("AI_ATTEMPT_TIMEOUT_MS", "1000");

    globalThis.fetch = (input, init) => {
      const url = input.toString();
      calls.push(url);
      if (url.includes("stalled-primary")) {
        return new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener(
            "abort",
            () => reject(new DOMException("aborted", "AbortError")),
            { once: true },
          );
        });
      }
      return Promise.resolve(validQuizResponse());
    };

    const generated = await generateQuestionsFromPdf(
      new TextEncoder().encode("%PDF-1.4 test"),
      "Timeout recovery",
      "timeout-test-request",
    );

    assertEquals(generated.model, "responsive-fallback");
    assertEquals(generated.questions.length, 10);
    assertEquals(calls.length, 2);
    assertEquals(calls[0].includes("stalled-primary"), true);
    assertEquals(calls[1].includes("responsive-fallback"), true);
  } finally {
    globalThis.fetch = previousFetch;
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});

Deno.test("an API_KEY_INVALID response is not retried or exposed", async () => {
  const environmentNames = [
    "AI_API_KEY",
    "AI_MODEL",
    "AI_FALLBACK_MODEL",
    "AI_FALLBACK_MODELS",
    "AI_API_BASE_URL",
    "AI_TIMEOUT_MS",
    "AI_ATTEMPT_TIMEOUT_MS",
  ];
  const previousEnvironment = new Map(
    environmentNames.map((name) => [name, Deno.env.get(name)]),
  );
  const previousFetch = globalThis.fetch;
  let calls = 0;

  try {
    Deno.env.set("AI_API_KEY", "invalid-test-key-never-sent");
    Deno.env.set("AI_MODEL", "primary-lite");
    Deno.env.set("AI_FALLBACK_MODEL", "fallback-lite");
    Deno.env.delete("AI_FALLBACK_MODELS");
    Deno.env.set("AI_API_BASE_URL", "https://provider.test/v1beta");

    globalThis.fetch = () => {
      calls += 1;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            error: {
              status: "INVALID_ARGUMENT",
              message: "sensitive provider detail must stay private",
              details: [{ reason: "API_KEY_INVALID" }],
            },
          }),
          { status: 400 },
        ),
      );
    };

    const error = await assertRejects(
      () =>
        generateQuestionsFromPdf(
          new TextEncoder().encode("%PDF-1.4 test"),
          "Credential handling",
          "credential-test-request",
        ),
      ApiError,
      "credentials or access policy",
    );
    assertEquals((error as ApiError).code, "ai-credentials-rejected");
    assertEquals(error.message.includes("sensitive provider detail"), false);
    assertEquals(calls, 1);
  } finally {
    globalThis.fetch = previousFetch;
    for (const [name, value] of previousEnvironment) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});

function validQuizResponse(): Response {
  const questions = Array.from({ length: 10 }, (_, index) => ({
    id: `q${index + 1}`,
    prompt: `Which stable fact belongs to question ${index + 1}?`,
    options: [
      `Correct ${index + 1}`,
      `Alternative A${index + 1}`,
      `Alternative B${index + 1}`,
      `Alternative C${index + 1}`,
    ],
    correct_index: 0,
    explanation: `The PDF supports stable fact ${index + 1}.`,
    source_page: 1,
  }));
  return new Response(
    JSON.stringify({
      candidates: [{
        content: {
          parts: [{ text: JSON.stringify({ questions }) }],
        },
      }],
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}
