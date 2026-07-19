import { useEffect, useRef, useState } from "react";
import { decodeQrFromImageData } from "../utils/qrDecode";

// Modal de scan ao vivo via webcam — primeiro uso de getUserMedia no
// projeto. No Linux o Tauri usa WebKitGTK (não Chromium), então o suporte a
// getUserMedia dentro da webview nunca foi validado antes desta feature;
// qualquer erro de acesso à câmera aparece inline, sem travar o resto do
// formulário (upload de imagem continua funcionando como alternativa).
export function TotpQrScanner({
  onDetected,
  onClose,
}: {
  onDetected: (raw: string) => void;
  onClose: () => void;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let stream: MediaStream | null = null;
    let rafId = 0;
    let cancelled = false;
    const canvas = document.createElement("canvas");

    function tick() {
      const video = videoRef.current;
      if (!video || video.readyState < video.HAVE_ENOUGH_DATA) {
        rafId = requestAnimationFrame(tick);
        return;
      }
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext("2d");
      if (ctx) {
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const raw = decodeQrFromImageData(imageData);
        if (raw) {
          onDetected(raw);
          return;
        }
      }
      rafId = requestAnimationFrame(tick);
    }

    async function start() {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "environment" },
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play();
        }
        tick();
      } catch (e) {
        if (!cancelled) setError(String(e));
      }
    }

    start();

    return () => {
      cancelled = true;
      cancelAnimationFrame(rafId);
      stream?.getTracks().forEach((t) => t.stop());
    };
  }, [onDetected]);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">Escanear QR do 2FA</h2>
          <button className="modal-close" onClick={onClose}>
            ✕
          </button>
        </div>
        {error ? (
          <p className="error-text" style={{ margin: 0 }}>
            Não foi possível acessar a câmera: {error}
          </p>
        ) : (
          <video
            ref={videoRef}
            muted
            playsInline
            style={{ width: "100%", borderRadius: 12, background: "#000" }}
          />
        )}
        <p className="muted" style={{ margin: "0.75rem 0 0", fontSize: "0.82em", textAlign: "center" }}>
          Aponte a câmera pro QR code da tela de configuração do 2FA
        </p>
      </div>
    </div>
  );
}
