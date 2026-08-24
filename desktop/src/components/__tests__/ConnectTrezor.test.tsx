import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { ConnectTrezor } from "../ConnectTrezor";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

const connectAsyncMock = vi.fn();
vi.mock("wagmi", () => ({
  useConnect: () => ({ connectAsync: connectAsyncMock }),
}));

vi.mock("../../connectors/trezor", () => ({
  trezor: { id: "trezor" },
  setTrezorAccountIndex: vi.fn(),
}));

// O componente faz polling via setInterval (mesmo padrão de ConnectLedger.tsx) —
// usamos timers reais com um timeout maior nas asserções em vez de fake timers,
// não há precedente de fake timers neste projeto e a interação entre elas e as
// Promises do invoke() mockado é frágil.
const POLL_TIMEOUT = { timeout: 3_000 };

describe("ConnectTrezor", () => {
  beforeEach(() => {
    invokeMock.mockReset();
    connectAsyncMock.mockReset();
  });

  it("shows the connectUsb step while the device isn't found", async () => {
    invokeMock.mockRejectedValue("not_connected");

    render(<ConnectTrezor onBack={vi.fn()} />);

    expect(await screen.findByText("Connect your Trezor via USB")).toBeInTheDocument();
    expect(screen.getByText("Unlock with your PIN on the device")).toBeInTheDocument();
    // sem passo de "abrir app" — diferente da Ledger, a Trezor não tem esse conceito
    expect(screen.queryByText(/open.*app/i)).not.toBeInTheDocument();
  }, 10_000);

  it("shows the not-initialized message for a fresh/wiped device", async () => {
    invokeMock.mockRejectedValue("not_initialized");

    render(<ConnectTrezor onBack={vi.fn()} />);

    await waitFor(
      () => expect(screen.getByText(/isn't set up yet/)).toBeInTheDocument(),
      POLL_TIMEOUT,
    );
  }, 10_000);

  it("shows the access-denied message when USB permissions are missing", async () => {
    invokeMock.mockRejectedValue("access_denied");

    render(<ConnectTrezor onBack={vi.fn()} />);

    await waitFor(
      () => expect(screen.getByText(/Could not access the Trezor/)).toBeInTheDocument(),
      POLL_TIMEOUT,
    );
  }, 10_000);

  it("moves to account selection once the device responds, listing 5 accounts", async () => {
    invokeMock.mockImplementation((cmd: string, args?: { accountIndex: number }) => {
      if (cmd === "get_trezor_address") {
        return Promise.resolve(`0x${String(args?.accountIndex ?? 0).padStart(40, "0")}`);
      }
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectTrezor onBack={vi.fn()} />);

    await waitFor(
      () => expect(screen.getByText("Select account")).toBeInTheDocument(),
      POLL_TIMEOUT,
    );

    expect(await screen.findByText("Account 0")).toBeInTheDocument();
    expect(screen.getByText("Account 4")).toBeInTheDocument();
  }, 10_000);

  it("calls onBack when the back button is clicked", async () => {
    invokeMock.mockRejectedValue("not_connected");
    const onBack = vi.fn();

    render(<ConnectTrezor onBack={onBack} />);

    (await screen.findByText(/Back/)).click();
    expect(onBack).toHaveBeenCalled();
  }, 10_000);
});
