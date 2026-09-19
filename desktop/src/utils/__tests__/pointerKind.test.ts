import { describe, it, expect } from "vitest";
import { pointerKind } from "../pointerKind";

describe("pointerKind", () => {
  it("reconhece ponteiro Arweave", () => {
    expect(pointerKind("ar://Abc123_-xyz")).toBe("arweave");
  });

  it("reconhece ponteiro Git", () => {
    expect(pointerKind("git:AQID@0123456789abcdef0123456789abcdef01234567")).toBe("git");
  });

  it("CID sem esquema é IPFS legado", () => {
    expect(pointerKind("QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG")).toBe("legacy-ipfs");
    expect(pointerKind("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi")).toBe("legacy-ipfs");
  });

  it("esquema desconhecido e string vazia continuam caindo em IPFS legado", () => {
    expect(pointerKind("http://example.com/x")).toBe("legacy-ipfs");
    expect(pointerKind("")).toBe("legacy-ipfs");
  });

  it("o prefixo é literal: maiúsculas e prefixos parciais não contam", () => {
    expect(pointerKind("AR://x")).toBe("legacy-ipfs");
    expect(pointerKind("xar://x")).toBe("legacy-ipfs");
    expect(pointerKind("mygit:x")).toBe("legacy-ipfs");
  });
});
