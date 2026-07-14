import QRCode from 'qrcode';

export async function renderQrToCanvas(
  canvas: HTMLCanvasElement,
  data: string,
): Promise<void> {
  await QRCode.toCanvas(canvas, data, { width: 256, margin: 1 });
}
