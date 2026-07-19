import jsQR from "jsqr";

// Formato mínimo compatível com o `ImageData` do DOM — permite testar
// decodeQrFromImageData() com um buffer construído à mão (ver
// __tests__/qrDecode.test.ts), sem depender de um `ImageData` real (jsdom
// não implementa canvas/decode de imagem de verdade).
export interface DecodableImage {
  data: Uint8ClampedArray;
  width: number;
  height: number;
}

// Decodifica um QR code a partir de pixels RGBA já extraídos (ex: de um
// <canvas> 2D context via getImageData, tanto no scan ao vivo pela webcam
// quanto no upload de uma imagem). Retorna null se não achar nenhum QR —
// nunca lança.
export function decodeQrFromImageData(image: DecodableImage): string | null {
  const result = jsQR(image.data, image.width, image.height);
  return result?.data ?? null;
}

// Decodifica um QR a partir dos bytes crus de um arquivo de imagem (PNG/JPG
// escolhido pelo usuário via diálogo nativo) — usa <img>+<canvas> do próprio
// navegador (webview do Tauri) pra rasterizar antes de decodificar. Só roda
// de verdade em runtime de browser; a lógica testável fica isolada em
// decodeQrFromImageData acima.
export async function decodeQrFromImageBytes(
  bytes: Uint8Array,
): Promise<string | null> {
  const blob = new Blob([new Uint8Array(bytes)]);
  const url = URL.createObjectURL(blob);
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const el = new Image();
      el.onload = () => resolve(el);
      el.onerror = () => reject(new Error("Could not load image"));
      el.src = url;
    });

    const canvas = document.createElement("canvas");
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;

    ctx.drawImage(img, 0, 0);
    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    return decodeQrFromImageData(imageData);
  } finally {
    URL.revokeObjectURL(url);
  }
}
