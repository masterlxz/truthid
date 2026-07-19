import { describe, expect, it } from "vitest";
import { create } from "qrcode";
import { decodeQrFromImageData, type DecodableImage } from "../qrDecode";

// jsdom não implementa canvas/decode de PNG de verdade, então não dá pra
// testar decodeQrFromImageBytes() (que depende de <img>/<canvas> reais) —
// mas dá pra provar decodeQrFromImageData() com um QR de verdade, gerado com
// `qrcode` (Node, sem canvas) e rasterizado à mão num buffer RGBA cru. Prova
// o pipeline de decode inteiro (jsQR + a matriz do QR), não só uma
// string solta.
function rasterize(text: string, scale = 4, margin = 4): DecodableImage {
  const qr = create(text, { errorCorrectionLevel: "M" });
  const moduleCount = qr.modules.size;
  const size = (moduleCount + margin * 2) * scale;
  const data = new Uint8ClampedArray(size * size * 4).fill(255);

  for (let row = 0; row < moduleCount; row++) {
    for (let col = 0; col < moduleCount; col++) {
      if (!qr.modules.get(row, col)) continue;
      for (let dy = 0; dy < scale; dy++) {
        for (let dx = 0; dx < scale; dx++) {
          const px = (col + margin) * scale + dx;
          const py = (row + margin) * scale + dy;
          const idx = (py * size + px) * 4;
          data[idx] = 0;
          data[idx + 1] = 0;
          data[idx + 2] = 0;
          data[idx + 3] = 255;
        }
      }
    }
  }

  return { data, width: size, height: size };
}

describe("decodeQrFromImageData", () => {
  it("decodifica um QR válido de volta pro texto original (otpauth:// URI)", () => {
    const uri =
      "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example";
    expect(decodeQrFromImageData(rasterize(uri))).toBe(uri);
  });

  it("decodifica um secret base32 cru", () => {
    const secret = "JBSWY3DPEHPK3PXP";
    expect(decodeQrFromImageData(rasterize(secret))).toBe(secret);
  });

  it("retorna null quando a imagem não tem nenhum QR", () => {
    const blank: DecodableImage = {
      data: new Uint8ClampedArray(100 * 100 * 4).fill(255),
      width: 100,
      height: 100,
    };
    expect(decodeQrFromImageData(blank)).toBeNull();
  });
});
