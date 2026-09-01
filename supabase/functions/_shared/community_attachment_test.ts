// Small offline tests for Community attachment byte validation.

import { sha256Hex, validateAttachmentBytes } from "./community_attachment.ts";

function expectThrows(work: () => void): void {
  let threw = false;
  try {
    work();
  } catch {
    threw = true;
  }
  if (!threw) throw new Error("Expected attachment validation to fail.");
}

Deno.test("accepts the five supported attachment signatures", () => {
  validateAttachmentBytes(
    new Uint8Array([0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9]),
    "image/jpeg",
  );
  validateAttachmentBytes(
    new Uint8Array([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]),
    "image/png",
  );
  validateAttachmentBytes(
    new Uint8Array([
      82,
      73,
      70,
      70,
      12,
      0,
      0,
      0,
      87,
      69,
      66,
      80,
      86,
      80,
      56,
      32,
      0,
      0,
      0,
      0,
    ]),
    "image/webp",
  );
  validateAttachmentBytes(
    new TextEncoder().encode("%PDF-1.4\n%%EOF\n"),
    "application/pdf",
  );
  validateAttachmentBytes(
    new TextEncoder().encode("A safe UTF-8 note.\n"),
    "text/plain",
  );
});

Deno.test("rejects misleading MIME labels and unsafe text controls", () => {
  const ordinaryText = new TextEncoder().encode("not an image");
  expectThrows(() => validateAttachmentBytes(ordinaryText, "image/jpeg"));
  expectThrows(() => validateAttachmentBytes(ordinaryText, "image/png"));
  expectThrows(() => validateAttachmentBytes(ordinaryText, "image/webp"));
  expectThrows(() => validateAttachmentBytes(ordinaryText, "application/pdf"));
  expectThrows(() =>
    validateAttachmentBytes(
      new Uint8Array([0x61, 0x00, 0x62]),
      "text/plain",
    )
  );
});

Deno.test("computes the expected lowercase SHA-256", async () => {
  const digest = await sha256Hex(new TextEncoder().encode("abc"));
  if (
    digest !==
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  ) {
    throw new Error("SHA-256 output did not match the known test vector.");
  }
});
