import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { ArweaveDashboard } from "../ArweaveDashboard";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

const ADDRESS = "arweave-address-1";

describe("ArweaveDashboard", () => {
  beforeEach(() => {
    invokeMock.mockReset();
  });

  it("shows the generate button when no wallet exists yet", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "arweave_wallet_exists") return Promise.resolve(false);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ArweaveDashboard />);

    expect(await screen.findByRole("button", { name: "Generate Arweave wallet" })).toBeInTheDocument();
  });

  it("shows balance and history once a wallet exists", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "arweave_wallet_exists") return Promise.resolve(true);
      if (cmd === "arweave_wallet_address") return Promise.resolve(ADDRESS);
      if (cmd === "arweave_wallet_balance") return Promise.resolve(String(2 * 1e12)); // 2 AR
      if (cmd === "arweave_wallet_transactions") {
        return Promise.resolve([
          {
            id: "tx1234567890",
            block_height: 100,
            block_timestamp: 1_700_000_000,
            fee_ar: "0.0001",
            quantity_ar: "0",
            recipient: null,
            app_name: "TruthID",
            content_type: "application/octet-stream",
          },
        ]);
      }
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ArweaveDashboard />);

    expect(await screen.findByText("Balance: 2.000000 AR")).toBeInTheDocument();
    expect(await screen.findByText("application/octet-stream")).toBeInTheDocument();
  });

  it("shows a pending transaction (null block) without crashing", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "arweave_wallet_exists") return Promise.resolve(true);
      if (cmd === "arweave_wallet_address") return Promise.resolve(ADDRESS);
      if (cmd === "arweave_wallet_balance") return Promise.resolve("0");
      if (cmd === "arweave_wallet_transactions") {
        return Promise.resolve([
          {
            id: "tx-pending-1234",
            block_height: null,
            block_timestamp: null,
            fee_ar: "0.0002",
            quantity_ar: "1.5",
            recipient: "0xRecipient",
            app_name: null,
            content_type: null,
          },
        ]);
      }
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ArweaveDashboard />);

    expect(await screen.findByText("Pending")).toBeInTheDocument();
    expect(await screen.findByText("1.5 AR")).toBeInTheDocument();
  });

  it("shows a retry option when history fails to load, without breaking the balance card", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "arweave_wallet_exists") return Promise.resolve(true);
      if (cmd === "arweave_wallet_address") return Promise.resolve(ADDRESS);
      if (cmd === "arweave_wallet_balance") return Promise.resolve(String(1e12));
      if (cmd === "arweave_wallet_transactions") return Promise.reject(new Error("POST /graphql retornou 500"));
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ArweaveDashboard />);

    expect(await screen.findByText("Balance: 1.000000 AR")).toBeInTheDocument();
    expect(await screen.findByText("Failed to load history: Error: POST /graphql retornou 500")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Retry" })).toBeInTheDocument();
  });

  it("preserves the zero-balance warning", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "arweave_wallet_exists") return Promise.resolve(true);
      if (cmd === "arweave_wallet_address") return Promise.resolve(ADDRESS);
      if (cmd === "arweave_wallet_balance") return Promise.resolve("0");
      if (cmd === "arweave_wallet_transactions") return Promise.resolve([]);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<ArweaveDashboard />);

    await waitFor(() =>
      expect(
        screen.getByText(
          'No balance yet — buy AR on an exchange and send it to the address above before clicking "Send".',
        ),
      ).toBeInTheDocument(),
    );
  });
});
