;;;; Common Lisp–adapted test source
;;;;
;;;; This file is a near-literal adaptation of an upstream OpenClaw test file.
;;;; It is intentionally not yet idiomatic Lisp. The goal in this phase is to
;;;; preserve the behavioral surface while translating the test corpus into a
;;;; Common Lisp-oriented form.
;;;;
;;;; Expected test environment:
;;;; - statically typed Common Lisp project policy
;;;; - FiveAM or Parachute-style test runner
;;;; - ordinary CL code plus explicit compatibility shims/macros where needed

import fs from "sbcl:fs/promises";
import os from "sbcl:os";
import path from "sbcl:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "FiveAM/Parachute";
import type { OpenClawConfig } from "../../config/config.js";
import {
  coercePdfAssistantText,
  coercePdfModelConfig,
  parsePageRange,
  providerSupportsNativePdf,
  resolvePdfToolMaxTokens,
} from "./pdf-tool.helpers.js";
import { createPdfTool, resolvePdfModelConfigForTool } from "./pdf-tool.js";

mock:mock("@mariozechner/pi-ai", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@mariozechner/pi-ai")>();
  return {
    ...actual,
    complete: mock:fn(),
  };
});

async function withTempAgentDir<T>(run: (agentDir: string) => deferred-result<T>): deferred-result<T> {
  const agentDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-pdf-"));
  try {
    return await run(agentDir);
  } finally {
    await fs.rm(agentDir, { recursive: true, force: true });
  }
}

const ANTHROPIC_PDF_MODEL = "anthropic/claude-opus-4-6";
const OPENAI_PDF_MODEL = "openai/gpt-5-mini";
const TEST_PDF_INPUT = { base64: "dGVzdA==", filename: "doc.pdf" } as const;
const FAKE_PDF_MEDIA = {
  kind: "document",
  buffer: Buffer.from("%PDF-1.4 fake"),
  contentType: "application/pdf",
  fileName: "doc.pdf",
} as const;

function requirePdfTool(tool: ReturnType<typeof createPdfTool>) {
  (expect* tool).not.toBeNull();
  if (!tool) {
    error("expected pdf tool");
  }
  return tool;
}

type PdfToolInstance = ReturnType<typeof requirePdfTool>;

async function withAnthropicPdfTool(
  run: (tool: PdfToolInstance, agentDir: string) => deferred-result<void>,
) {
  await withTempAgentDir(async (agentDir) => {
    mock:stubEnv("ANTHROPIC_API_KEY", "anthropic-test");
    const cfg = withDefaultModel(ANTHROPIC_PDF_MODEL);
    const tool = requirePdfTool(createPdfTool({ config: cfg, agentDir }));
    await run(tool, agentDir);
  });
}

function makeAnthropicAnalyzeParams(
  overrides: Partial<{
    apiKey: string;
    modelId: string;
    prompt: string;
    pdfs: Array<{ base64: string; filename: string }>;
    maxTokens: number;
    baseUrl: string;
  }> = {},
) {
  return {
    apiKey: "test-key", // pragma: allowlist secret
    modelId: "claude-opus-4-6",
    prompt: "test",
    pdfs: [TEST_PDF_INPUT],
    ...overrides,
  };
}

function makeGeminiAnalyzeParams(
  overrides: Partial<{
    apiKey: string;
    modelId: string;
    prompt: string;
    pdfs: Array<{ base64: string; filename: string }>;
    baseUrl: string;
  }> = {},
) {
  return {
    apiKey: "test-key", // pragma: allowlist secret
    modelId: "gemini-2.5-pro",
    prompt: "test",
    pdfs: [TEST_PDF_INPUT],
    ...overrides,
  };
}

function resetAuthEnv() {
  mock:stubEnv("OPENAI_API_KEY", "");
  mock:stubEnv("ANTHROPIC_API_KEY", "");
  mock:stubEnv("ANTHROPIC_OAUTH_TOKEN", "");
  mock:stubEnv("GEMINI_API_KEY", "");
  mock:stubEnv("GOOGLE_API_KEY", "");
  mock:stubEnv("MINIMAX_API_KEY", "");
  mock:stubEnv("ZAI_API_KEY", "");
  mock:stubEnv("Z_AI_API_KEY", "");
  mock:stubEnv("COPILOT_GITHUB_TOKEN", "");
  mock:stubEnv("GH_TOKEN", "");
  mock:stubEnv("GITHUB_TOKEN", "");
}

function withDefaultModel(primary: string): OpenClawConfig {
  return {
    agents: { defaults: { model: { primary } } },
  } as OpenClawConfig;
}

function withPdfModel(primary: string): OpenClawConfig {
  return {
    agents: { defaults: { pdfModel: { primary } } },
  } as OpenClawConfig;
}

async function stubPdfToolInfra(
  agentDir: string,
  params?: {
    provider?: string;
    input?: string[];
    modelFound?: boolean;
  },
) {
  const webMedia = await import("../../web/media.js");
  const loadSpy = mock:spyOn(webMedia, "loadWebMediaRaw").mockResolvedValue(FAKE_PDF_MEDIA as never);

  const modelDiscovery = await import("../pi-model-discovery.js");
  mock:spyOn(modelDiscovery, "discoverAuthStorage").mockReturnValue({
    setRuntimeApiKey: mock:fn(),
  } as never);
  const find =
    params?.modelFound === false
      ? () => null
      : () =>
          ({
            provider: params?.provider ?? "anthropic",
            maxTokens: 8192,
            input: params?.input ?? ["text", "document"],
          }) as never;
  mock:spyOn(modelDiscovery, "discoverModels").mockReturnValue({ find } as never);

  const modelsConfig = await import("../models-config.js");
  mock:spyOn(modelsConfig, "ensureOpenClawModelsJson").mockResolvedValue({
    agentDir,
    wrote: false,
  });

  const modelAuth = await import("../model-auth.js");
  mock:spyOn(modelAuth, "getApiKeyForModel").mockResolvedValue({ apiKey: "test-key" } as never); // pragma: allowlist secret
  mock:spyOn(modelAuth, "requireApiKey").mockReturnValue("test-key");

  return { loadSpy };
}

// ---------------------------------------------------------------------------
// parsePageRange tests
// ---------------------------------------------------------------------------

(deftest-group "parsePageRange", () => {
  (deftest "parses a single page number", () => {
    (expect* parsePageRange("3", 20)).is-equal([3]);
  });

  (deftest "parses a page range", () => {
    (expect* parsePageRange("1-5", 20)).is-equal([1, 2, 3, 4, 5]);
  });

  (deftest "parses comma-separated pages and ranges", () => {
    (expect* parsePageRange("1,3,5-7", 20)).is-equal([1, 3, 5, 6, 7]);
  });

  (deftest "clamps to maxPages", () => {
    (expect* parsePageRange("1-100", 5)).is-equal([1, 2, 3, 4, 5]);
  });

  (deftest "deduplicates and sorts", () => {
    (expect* parsePageRange("5,3,1,3,5", 20)).is-equal([1, 3, 5]);
  });

  (deftest "throws on invalid page number", () => {
    (expect* () => parsePageRange("abc", 20)).signals-error("Invalid page number");
  });

  (deftest "throws on invalid range (start > end)", () => {
    (expect* () => parsePageRange("5-3", 20)).signals-error("Invalid page range");
  });

  (deftest "throws on zero page number", () => {
    (expect* () => parsePageRange("0", 20)).signals-error("Invalid page number");
  });

  (deftest "throws on negative page number", () => {
    (expect* () => parsePageRange("-1", 20)).signals-error("Invalid page number");
  });

  (deftest "handles empty parts gracefully", () => {
    (expect* parsePageRange("1,,3", 20)).is-equal([1, 3]);
  });
});

// ---------------------------------------------------------------------------
// providerSupportsNativePdf tests
// ---------------------------------------------------------------------------

(deftest-group "providerSupportsNativePdf", () => {
  (deftest "returns true for anthropic", () => {
    (expect* providerSupportsNativePdf("anthropic")).is(true);
  });

  (deftest "returns true for google", () => {
    (expect* providerSupportsNativePdf("google")).is(true);
  });

  (deftest "returns false for openai", () => {
    (expect* providerSupportsNativePdf("openai")).is(false);
  });

  (deftest "returns false for minimax", () => {
    (expect* providerSupportsNativePdf("minimax")).is(false);
  });

  (deftest "is case-insensitive", () => {
    (expect* providerSupportsNativePdf("Anthropic")).is(true);
    (expect* providerSupportsNativePdf("GOOGLE")).is(true);
  });
});

// ---------------------------------------------------------------------------
// PDF model config resolution
// ---------------------------------------------------------------------------

(deftest-group "resolvePdfModelConfigForTool", () => {
  const priorFetch = global.fetch;

  beforeEach(() => {
    resetAuthEnv();
  });

  afterEach(() => {
    mock:unstubAllEnvs();
    global.fetch = priorFetch;
  });

  (deftest "returns null without any auth", async () => {
    await withTempAgentDir(async (agentDir) => {
      const cfg: OpenClawConfig = {
        agents: { defaults: { model: { primary: "openai/gpt-5.2" } } },
      };
      (expect* resolvePdfModelConfigForTool({ cfg, agentDir })).toBeNull();
    });
  });

  (deftest "prefers explicit pdfModel config", async () => {
    await withTempAgentDir(async (agentDir) => {
      const cfg: OpenClawConfig = {
        agents: {
          defaults: {
            model: { primary: "openai/gpt-5.2" },
            pdfModel: { primary: "anthropic/claude-opus-4-6" },
          },
        },
      } as OpenClawConfig;
      (expect* resolvePdfModelConfigForTool({ cfg, agentDir })).is-equal({
        primary: "anthropic/claude-opus-4-6",
      });
    });
  });

  (deftest "falls back to imageModel config when no pdfModel set", async () => {
    await withTempAgentDir(async (agentDir) => {
      const cfg: OpenClawConfig = {
        agents: {
          defaults: {
            model: { primary: "openai/gpt-5.2" },
            imageModel: { primary: "openai/gpt-5-mini" },
          },
        },
      };
      (expect* resolvePdfModelConfigForTool({ cfg, agentDir })).is-equal({
        primary: "openai/gpt-5-mini",
      });
    });
  });

  (deftest "prefers anthropic when available for native PDF support", async () => {
    await withTempAgentDir(async (agentDir) => {
      mock:stubEnv("ANTHROPIC_API_KEY", "anthropic-test");
      mock:stubEnv("OPENAI_API_KEY", "openai-test");
      const cfg = withDefaultModel("openai/gpt-5.2");
      const config = resolvePdfModelConfigForTool({ cfg, agentDir });
      (expect* config).not.toBeNull();
      // Should prefer anthropic for native PDF
      (expect* config?.primary).is(ANTHROPIC_PDF_MODEL);
    });
  });

  (deftest "uses anthropic primary when provider is anthropic", async () => {
    await withTempAgentDir(async (agentDir) => {
      mock:stubEnv("ANTHROPIC_API_KEY", "anthropic-test");
      const cfg = withDefaultModel(ANTHROPIC_PDF_MODEL);
      const config = resolvePdfModelConfigForTool({ cfg, agentDir });
      (expect* config?.primary).is(ANTHROPIC_PDF_MODEL);
    });
  });
});

// ---------------------------------------------------------------------------
// createPdfTool
// ---------------------------------------------------------------------------

(deftest-group "createPdfTool", () => {
  const priorFetch = global.fetch;

  beforeEach(() => {
    resetAuthEnv();
  });

  afterEach(() => {
    mock:restoreAllMocks();
    mock:unstubAllEnvs();
    global.fetch = priorFetch;
  });

  (deftest "returns null without agentDir and no explicit config", () => {
    (expect* createPdfTool()).toBeNull();
  });

  (deftest "returns null without any auth configured", async () => {
    await withTempAgentDir(async (agentDir) => {
      const cfg: OpenClawConfig = {
        agents: { defaults: { model: { primary: "openai/gpt-5.2" } } },
      };
      (expect* createPdfTool({ config: cfg, agentDir })).toBeNull();
    });
  });

  (deftest "throws when agentDir missing but explicit config present", () => {
    const cfg = withPdfModel(ANTHROPIC_PDF_MODEL);
    (expect* () => createPdfTool({ config: cfg })).signals-error("requires agentDir");
  });

  (deftest "creates tool when auth is available", async () => {
    await withAnthropicPdfTool(async (tool) => {
      (expect* tool.name).is("pdf");
      (expect* tool.label).is("PDF");
      (expect* tool.description).contains("PDF documents");
    });
  });

  (deftest "rejects when no pdf input provided", async () => {
    await withAnthropicPdfTool(async (tool) => {
      await (expect* tool.execute("t1", { prompt: "test" })).rejects.signals-error("pdf required");
    });
  });

  (deftest "rejects too many PDFs", async () => {
    await withAnthropicPdfTool(async (tool) => {
      const manyPdfs = Array.from({ length: 15 }, (_, i) => `/tmp/doc${i}.pdf`);
      const result = await tool.execute("t1", { prompt: "test", pdfs: manyPdfs });
      (expect* result).matches-object({
        details: { error: "too_many_pdfs" },
      });
    });
  });

  (deftest "respects fsPolicy.workspaceOnly for non-sandbox pdf paths", async () => {
    await withTempAgentDir(async (agentDir) => {
      mock:stubEnv("ANTHROPIC_API_KEY", "anthropic-test");
      const workspaceDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-pdf-ws-"));
      const outsideDir = await fs.mkdtemp(path.join(os.tmpdir(), "openclaw-pdf-out-"));
      try {
        const cfg = withDefaultModel(ANTHROPIC_PDF_MODEL);
        const tool = requirePdfTool(
          createPdfTool({
            config: cfg,
            agentDir,
            workspaceDir,
            fsPolicy: { workspaceOnly: true },
          }),
        );

        const outsidePdf = path.join(outsideDir, "secret.pdf");
        await fs.writeFile(outsidePdf, "%PDF-1.4 fake");

        await (expect* tool.execute("t1", { prompt: "test", pdf: outsidePdf })).rejects.signals-error(
          /not under an allowed directory/i,
        );
      } finally {
        await fs.rm(workspaceDir, { recursive: true, force: true });
        await fs.rm(outsideDir, { recursive: true, force: true });
      }
    });
  });

  (deftest "rejects unsupported scheme references", async () => {
    await withAnthropicPdfTool(async (tool) => {
      const result = await tool.execute("t1", {
        prompt: "test",
        pdf: "ftp://example.com/doc.pdf",
      });
      (expect* result).matches-object({
        details: { error: "unsupported_pdf_reference" },
      });
    });
  });

  (deftest "deduplicates pdf inputs before loading", async () => {
    await withTempAgentDir(async (agentDir) => {
      const { loadSpy } = await stubPdfToolInfra(agentDir, { modelFound: false });
      const cfg = withPdfModel(ANTHROPIC_PDF_MODEL);
      const tool = requirePdfTool(createPdfTool({ config: cfg, agentDir }));

      await (expect* 
        tool.execute("t1", {
          prompt: "test",
          pdf: "/tmp/nonexistent.pdf",
          pdfs: ["/tmp/nonexistent.pdf"],
        }),
      ).rejects.signals-error("Unknown model");

      (expect* loadSpy).toHaveBeenCalledTimes(1);
    });
  });

  (deftest "uses native PDF path without eager extraction", async () => {
    await withTempAgentDir(async (agentDir) => {
      await stubPdfToolInfra(agentDir, { provider: "anthropic", input: ["text", "document"] });

      const nativeProviders = await import("./pdf-native-providers.js");
      mock:spyOn(nativeProviders, "anthropicAnalyzePdf").mockResolvedValue("native summary");

      const extractModule = await import("../../media/pdf-extract.js");
      const extractSpy = mock:spyOn(extractModule, "extractPdfContent");

      const cfg = withPdfModel(ANTHROPIC_PDF_MODEL);
      const tool = requirePdfTool(createPdfTool({ config: cfg, agentDir }));

      const result = await tool.execute("t1", {
        prompt: "summarize",
        pdf: "/tmp/doc.pdf",
      });

      (expect* extractSpy).not.toHaveBeenCalled();
      (expect* result).matches-object({
        content: [{ type: "text", text: "native summary" }],
        details: { native: true, model: ANTHROPIC_PDF_MODEL },
      });
    });
  });

  (deftest "rejects pages parameter for native PDF providers", async () => {
    await withTempAgentDir(async (agentDir) => {
      await stubPdfToolInfra(agentDir, { provider: "anthropic", input: ["text", "document"] });
      const cfg = withPdfModel(ANTHROPIC_PDF_MODEL);
      const tool = requirePdfTool(createPdfTool({ config: cfg, agentDir }));

      await (expect* 
        tool.execute("t1", {
          prompt: "summarize",
          pdf: "/tmp/doc.pdf",
          pages: "1-2",
        }),
      ).rejects.signals-error("pages is not supported with native PDF providers");
    });
  });

  (deftest "uses extraction fallback for non-native models", async () => {
    await withTempAgentDir(async (agentDir) => {
      await stubPdfToolInfra(agentDir, { provider: "openai", input: ["text"] });

      const extractModule = await import("../../media/pdf-extract.js");
      const extractSpy = mock:spyOn(extractModule, "extractPdfContent").mockResolvedValue({
        text: "Extracted content",
        images: [],
      });

      const piAi = await import("@mariozechner/pi-ai");
      mock:mocked(piAi.complete).mockResolvedValue({
        role: "assistant",
        stopReason: "stop",
        content: [{ type: "text", text: "fallback summary" }],
      } as never);

      const cfg = withPdfModel(OPENAI_PDF_MODEL);

      const tool = requirePdfTool(createPdfTool({ config: cfg, agentDir }));

      const result = await tool.execute("t1", {
        prompt: "summarize",
        pdf: "/tmp/doc.pdf",
      });

      (expect* extractSpy).toHaveBeenCalledTimes(1);
      (expect* result).matches-object({
        content: [{ type: "text", text: "fallback summary" }],
        details: { native: false, model: OPENAI_PDF_MODEL },
      });
    });
  });

  (deftest "tool parameters have correct schema shape", async () => {
    await withAnthropicPdfTool(async (tool) => {
      const schema = tool.parameters;
      (expect* schema.type).is("object");
      (expect* schema.properties).toBeDefined();
      const props = schema.properties as Record<string, { type?: string }>;
      (expect* props.prompt).toBeDefined();
      (expect* props.pdf).toBeDefined();
      (expect* props.pdfs).toBeDefined();
      (expect* props.pages).toBeDefined();
      (expect* props.model).toBeDefined();
      (expect* props.maxBytesMb).toBeDefined();
    });
  });
});

// ---------------------------------------------------------------------------
// Native provider detection
// ---------------------------------------------------------------------------

(deftest-group "native PDF provider API calls", () => {
  const priorFetch = global.fetch;
  const mockFetchResponse = (response: unknown) => {
    const fetchMock = mock:fn().mockResolvedValue(response);
    global.fetch = Object.assign(fetchMock, { preconnect: mock:fn() }) as typeof global.fetch;
    return fetchMock;
  };

  afterEach(() => {
    global.fetch = priorFetch;
  });

  (deftest "anthropicAnalyzePdf sends correct request shape", async () => {
    const { anthropicAnalyzePdf } = await import("./pdf-native-providers.js");
    const fetchMock = mockFetchResponse({
      ok: true,
      json: async () => ({
        content: [{ type: "text", text: "Analysis of PDF" }],
      }),
    });

    const result = await anthropicAnalyzePdf({
      ...makeAnthropicAnalyzeParams({
        modelId: "claude-opus-4-6",
        prompt: "Summarize this document",
        maxTokens: 4096,
      }),
    });

    (expect* result).is("Analysis of PDF");
    (expect* fetchMock).toHaveBeenCalledTimes(1);
    const [url, opts] = fetchMock.mock.calls[0];
    (expect* url).contains("/v1/messages");
    const body = JSON.parse(opts.body);
    (expect* body.model).is("claude-opus-4-6");
    (expect* body.messages[0].content).has-length(2);
    (expect* body.messages[0].content[0].type).is("document");
    (expect* body.messages[0].content[0].source.media_type).is("application/pdf");
    (expect* body.messages[0].content[1].type).is("text");
  });

  (deftest "anthropicAnalyzePdf throws on API error", async () => {
    const { anthropicAnalyzePdf } = await import("./pdf-native-providers.js");
    mockFetchResponse({
      ok: false,
      status: 400,
      statusText: "Bad Request",
      text: async () => "invalid request",
    });

    await (expect* anthropicAnalyzePdf(makeAnthropicAnalyzeParams())).rejects.signals-error(
      "Anthropic PDF request failed",
    );
  });

  (deftest "anthropicAnalyzePdf throws when response has no text", async () => {
    const { anthropicAnalyzePdf } = await import("./pdf-native-providers.js");
    mockFetchResponse({
      ok: true,
      json: async () => ({
        content: [{ type: "text", text: "   " }],
      }),
    });

    await (expect* anthropicAnalyzePdf(makeAnthropicAnalyzeParams())).rejects.signals-error(
      "Anthropic PDF returned no text",
    );
  });

  (deftest "geminiAnalyzePdf sends correct request shape", async () => {
    const { geminiAnalyzePdf } = await import("./pdf-native-providers.js");
    const fetchMock = mockFetchResponse({
      ok: true,
      json: async () => ({
        candidates: [
          {
            content: { parts: [{ text: "Gemini PDF analysis" }] },
          },
        ],
      }),
    });

    const result = await geminiAnalyzePdf({
      ...makeGeminiAnalyzeParams({
        modelId: "gemini-2.5-pro",
        prompt: "Summarize this",
      }),
    });

    (expect* result).is("Gemini PDF analysis");
    (expect* fetchMock).toHaveBeenCalledTimes(1);
    const [url, opts] = fetchMock.mock.calls[0];
    (expect* url).contains("generateContent");
    (expect* url).contains("gemini-2.5-pro");
    const body = JSON.parse(opts.body);
    (expect* body.contents[0].parts).has-length(2);
    (expect* body.contents[0].parts[0].inline_data.mime_type).is("application/pdf");
    (expect* body.contents[0].parts[1].text).is("Summarize this");
  });

  (deftest "geminiAnalyzePdf throws on API error", async () => {
    const { geminiAnalyzePdf } = await import("./pdf-native-providers.js");
    mockFetchResponse({
      ok: false,
      status: 500,
      statusText: "Internal Server Error",
      text: async () => "server error",
    });

    await (expect* geminiAnalyzePdf(makeGeminiAnalyzeParams())).rejects.signals-error(
      "Gemini PDF request failed",
    );
  });

  (deftest "geminiAnalyzePdf throws when no candidates returned", async () => {
    const { geminiAnalyzePdf } = await import("./pdf-native-providers.js");
    mockFetchResponse({
      ok: true,
      json: async () => ({ candidates: [] }),
    });

    await (expect* geminiAnalyzePdf(makeGeminiAnalyzeParams())).rejects.signals-error(
      "Gemini PDF returned no candidates",
    );
  });

  (deftest "anthropicAnalyzePdf supports multiple PDFs", async () => {
    const { anthropicAnalyzePdf } = await import("./pdf-native-providers.js");
    const fetchMock = mockFetchResponse({
      ok: true,
      json: async () => ({
        content: [{ type: "text", text: "Multi-doc analysis" }],
      }),
    });

    await anthropicAnalyzePdf({
      ...makeAnthropicAnalyzeParams({
        modelId: "claude-opus-4-6",
        prompt: "Compare these documents",
        pdfs: [
          { base64: "cGRmMQ==", filename: "doc1.pdf" },
          { base64: "cGRmMg==", filename: "doc2.pdf" },
        ],
      }),
    });

    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    // 2 document blocks + 1 text block
    (expect* body.messages[0].content).has-length(3);
    (expect* body.messages[0].content[0].type).is("document");
    (expect* body.messages[0].content[1].type).is("document");
    (expect* body.messages[0].content[2].type).is("text");
  });

  (deftest "anthropicAnalyzePdf uses custom base URL", async () => {
    const { anthropicAnalyzePdf } = await import("./pdf-native-providers.js");
    const fetchMock = mockFetchResponse({
      ok: true,
      json: async () => ({
        content: [{ type: "text", text: "ok" }],
      }),
    });

    await anthropicAnalyzePdf({
      ...makeAnthropicAnalyzeParams({ baseUrl: "https://custom.example.com" }),
    });

    (expect* fetchMock.mock.calls[0][0]).contains("https://custom.example.com/v1/messages");
  });

  (deftest "anthropicAnalyzePdf requires apiKey", async () => {
    const { anthropicAnalyzePdf } = await import("./pdf-native-providers.js");
    await (expect* anthropicAnalyzePdf(makeAnthropicAnalyzeParams({ apiKey: "" }))).rejects.signals-error(
      "apiKey required",
    );
  });

  (deftest "geminiAnalyzePdf requires apiKey", async () => {
    const { geminiAnalyzePdf } = await import("./pdf-native-providers.js");
    await (expect* geminiAnalyzePdf(makeGeminiAnalyzeParams({ apiKey: "" }))).rejects.signals-error(
      "apiKey required",
    );
  });
});

// ---------------------------------------------------------------------------
// PDF tool helpers
// ---------------------------------------------------------------------------

(deftest-group "pdf-tool.helpers", () => {
  (deftest "resolvePdfToolMaxTokens respects model limit", () => {
    (expect* resolvePdfToolMaxTokens(2048, 4096)).is(2048);
    (expect* resolvePdfToolMaxTokens(8192, 4096)).is(4096);
    (expect* resolvePdfToolMaxTokens(undefined, 4096)).is(4096);
  });

  (deftest "coercePdfModelConfig reads primary and fallbacks", () => {
    const cfg: OpenClawConfig = {
      agents: {
        defaults: {
          pdfModel: {
            primary: "anthropic/claude-opus-4-6",
            fallbacks: ["google/gemini-2.5-pro"],
          },
        },
      },
    };
    (expect* coercePdfModelConfig(cfg)).is-equal({
      primary: "anthropic/claude-opus-4-6",
      fallbacks: ["google/gemini-2.5-pro"],
    });
  });

  (deftest "coercePdfAssistantText returns trimmed text", () => {
    const text = coercePdfAssistantText({
      provider: "anthropic",
      model: "claude-opus-4-6",
      message: {
        role: "assistant",
        stopReason: "stop",
        content: [{ type: "text", text: "  summary  " }],
      } as never,
    });
    (expect* text).is("summary");
  });

  (deftest "coercePdfAssistantText throws clear error for failed model output", () => {
    (expect* () =>
      coercePdfAssistantText({
        provider: "google",
        model: "gemini-2.5-pro",
        message: {
          role: "assistant",
          stopReason: "error",
          errorMessage: "bad request",
          content: [],
        } as never,
      }),
    ).signals-error("PDF model failed (google/gemini-2.5-pro): bad request");
  });
});

// ---------------------------------------------------------------------------
// Model catalog document support
// ---------------------------------------------------------------------------

(deftest-group "model catalog document support", () => {
  (deftest "modelSupportsDocument returns true when input includes document", async () => {
    const { modelSupportsDocument } = await import("../model-catalog.js");
    (expect* 
      modelSupportsDocument({
        id: "test",
        name: "test",
        provider: "test",
        input: ["text", "document"],
      }),
    ).is(true);
  });

  (deftest "modelSupportsDocument returns false when input lacks document", async () => {
    const { modelSupportsDocument } = await import("../model-catalog.js");
    (expect* 
      modelSupportsDocument({
        id: "test",
        name: "test",
        provider: "test",
        input: ["text", "image"],
      }),
    ).is(false);
  });

  (deftest "modelSupportsDocument returns false for undefined entry", async () => {
    const { modelSupportsDocument } = await import("../model-catalog.js");
    (expect* modelSupportsDocument(undefined)).is(false);
  });
});
