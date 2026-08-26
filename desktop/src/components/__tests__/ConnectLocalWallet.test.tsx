import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { ConnectLocalWallet } from "../ConnectLocalWallet";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

const saveMock = vi.fn();
vi.mock("@tauri-apps/plugin-dialog", () => ({
  save: (...args: unknown[]) => saveMock(...args),
  open: vi.fn(),
}));

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeFile: vi.fn(),
  readFile: vi.fn(),
}));

const connectAsyncMock = vi.fn();
vi.mock("wagmi", () => ({
  useConnect: () => ({ connectAsync: connectAsyncMock }),
}));

vi.mock("../../connectors/localWallet", () => ({
  localWallet: { id: "localWallet" },
}));

const ADDRESS = "0xabc0000000000000000000000000000000000abc";

describe("ConnectLocalWallet", () => {
  beforeEach(() => {
    invokeMock.mockReset();
    saveMock.mockReset();
    connectAsyncMock.mockReset();
  });

  it("shows the intro warning before any key is generated", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(false);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectLocalWallet onBack={vi.fn()} />);

    expect(
      await screen.findByText(/only on this computer/i),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create local wallet" })).toBeInTheDocument();
  });

  it("calls onBack when the back button is clicked", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(false);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    const onBack = vi.fn();
    render(<ConnectLocalWallet onBack={onBack} />);

    await userEvent.click(screen.getByText(/Back/));
    expect(onBack).toHaveBeenCalled();
  });

  it("generates the wallet and shows the address + backup gate, without connecting yet", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(false);
      if (cmd === "local_wallet_generate") return Promise.resolve(ADDRESS);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectLocalWallet onBack={vi.fn()} />);

    await userEvent.click(await screen.findByRole("button", { name: "Create local wallet" }));

    expect(await screen.findByText(ADDRESS)).toBeInTheDocument();
    expect(screen.getByText("Backup required")).toBeInTheDocument();
    expect(connectAsyncMock).not.toHaveBeenCalled();
  });

  it("shows an error if local_wallet_generate fails", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(false);
      if (cmd === "local_wallet_generate") return Promise.reject("já existe uma wallet local neste device");
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectLocalWallet onBack={vi.fn()} />);

    await userEvent.click(await screen.findByRole("button", { name: "Create local wallet" }));

    expect(await screen.findByText("já existe uma wallet local neste device")).toBeInTheDocument();
  });

  it("only calls connectAsync after the backup gate is confirmed (already-exported checkbox)", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(false);
      if (cmd === "local_wallet_generate") return Promise.resolve(ADDRESS);
      if (cmd === "confirm_local_wallet_backup") return Promise.resolve(undefined);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    connectAsyncMock.mockResolvedValue(undefined);

    render(<ConnectLocalWallet onBack={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "Create local wallet" }));
    await screen.findByText("Backup required");

    expect(connectAsyncMock).not.toHaveBeenCalled();

    await userEvent.click(screen.getByText("I already exported a backup of this vault elsewhere"));
    await userEvent.click(screen.getByText("Confirm and continue"));

    await waitFor(() => expect(connectAsyncMock).toHaveBeenCalledWith({ connector: { id: "localWallet" } }));
    expect(invokeMock).toHaveBeenCalledWith("confirm_local_wallet_backup");
  });

  it("shows the existing-wallet screen with a Connect button when a local wallet already exists, without ever calling local_wallet_generate", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(true);
      if (cmd === "local_wallet_address") return Promise.resolve(ADDRESS);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectLocalWallet onBack={vi.fn()} />);

    expect(await screen.findByText(ADDRESS)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Connect" })).toBeInTheDocument();
    expect(invokeMock).not.toHaveBeenCalledWith("local_wallet_generate");
  });

  it("calls connectAsync directly when Connect is clicked on the existing-wallet screen", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(true);
      if (cmd === "local_wallet_address") return Promise.resolve(ADDRESS);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    connectAsyncMock.mockResolvedValue(undefined);

    render(<ConnectLocalWallet onBack={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "Connect" }));

    await waitFor(() => expect(connectAsyncMock).toHaveBeenCalledWith({ connector: { id: "localWallet" } }));
    expect(invokeMock).not.toHaveBeenCalledWith("local_wallet_generate");
  });

  it("shows an error and re-enables the Connect button if connectAsync rejects", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(true);
      if (cmd === "local_wallet_address") return Promise.resolve(ADDRESS);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    connectAsyncMock.mockRejectedValue(new Error("boom"));

    render(<ConnectLocalWallet onBack={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "Connect" }));

    expect(await screen.findByText("Error: boom")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Connect" })).not.toBeDisabled();
  });

  it("disables the create button while local_wallet_generate is in flight, and only invokes it once", async () => {
    let resolveGenerate!: (addr: string) => void;
    const generatePromise = new Promise<string>((resolve) => {
      resolveGenerate = resolve;
    });
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(false);
      if (cmd === "local_wallet_generate") return generatePromise;
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectLocalWallet onBack={vi.fn()} />);
    const button = await screen.findByRole("button", { name: "Create local wallet" });

    await userEvent.click(button);
    expect(button).toBeDisabled();

    await userEvent.click(button);
    expect(invokeMock.mock.calls.filter((c) => c[0] === "local_wallet_generate")).toHaveLength(1);

    resolveGenerate(ADDRESS);
    expect(await screen.findByText(ADDRESS)).toBeInTheDocument();
  });

  it("falls back to the create flow if local_wallet_exists rejects", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.reject("boom");
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectLocalWallet onBack={vi.fn()} />);

    expect(await screen.findByRole("button", { name: "Create local wallet" })).toBeInTheDocument();
  });
});
