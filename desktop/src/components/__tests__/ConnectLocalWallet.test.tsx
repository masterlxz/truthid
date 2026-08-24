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

  it("shows the intro warning before any key is generated", () => {
    render(<ConnectLocalWallet onBack={vi.fn()} />);

    expect(
      screen.getByText(/only on this computer/i),
    ).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create local wallet" })).toBeInTheDocument();
  });

  it("calls onBack when the back button is clicked", async () => {
    const onBack = vi.fn();
    render(<ConnectLocalWallet onBack={onBack} />);

    await userEvent.click(screen.getByText(/Back/));
    expect(onBack).toHaveBeenCalled();
  });

  it("generates the wallet and shows the address + backup gate, without connecting yet", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_generate") return Promise.resolve(ADDRESS);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ConnectLocalWallet onBack={vi.fn()} />);

    await userEvent.click(screen.getByRole("button", { name: "Create local wallet" }));

    expect(await screen.findByText(ADDRESS)).toBeInTheDocument();
    expect(screen.getByText("Backup required")).toBeInTheDocument();
    expect(connectAsyncMock).not.toHaveBeenCalled();
  });

  it("shows an error if local_wallet_generate fails", async () => {
    invokeMock.mockRejectedValueOnce("já existe uma wallet local neste device");

    render(<ConnectLocalWallet onBack={vi.fn()} />);

    await userEvent.click(screen.getByRole("button", { name: "Create local wallet" }));

    expect(await screen.findByText("já existe uma wallet local neste device")).toBeInTheDocument();
  });

  it("only calls connectAsync after the backup gate is confirmed (already-exported checkbox)", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_generate") return Promise.resolve(ADDRESS);
      if (cmd === "confirm_local_wallet_backup") return Promise.resolve(undefined);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    connectAsyncMock.mockResolvedValue(undefined);

    render(<ConnectLocalWallet onBack={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "Create local wallet" }));
    await screen.findByText("Backup required");

    expect(connectAsyncMock).not.toHaveBeenCalled();

    await userEvent.click(screen.getByText("I already exported a backup of this vault elsewhere"));
    await userEvent.click(screen.getByText("Confirm and continue"));

    await waitFor(() => expect(connectAsyncMock).toHaveBeenCalledWith({ connector: { id: "localWallet" } }));
    expect(invokeMock).toHaveBeenCalledWith("confirm_local_wallet_backup");
  });
});
