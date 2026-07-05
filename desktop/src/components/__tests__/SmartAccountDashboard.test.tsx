import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SmartAccountDashboard } from "../SmartAccountDashboard";
import type { SmartAccountActivity } from "../../types";

vi.mock("wagmi", () => ({
  useBalance: vi.fn(),
  useAccount: vi.fn(),
  useWriteContract: vi.fn(),
  useWaitForTransactionReceipt: vi.fn(),
}));

vi.mock("@tanstack/react-query", () => ({
  useQueryClient: vi.fn(),
}));

vi.mock("../../contexts/IdentityContext", () => ({
  useIdentity: vi.fn(),
}));

vi.mock("../../contexts/WalletModalContext", () => ({
  useWalletModal: vi.fn(),
}));

vi.mock("../../hooks/useSmartAccountActivity", () => ({
  useSmartAccountActivity: vi.fn(),
}));

import {
  useBalance,
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { useIdentity } from "../../contexts/IdentityContext";
import { useWalletModal } from "../../contexts/WalletModalContext";
import { useSmartAccountActivity } from "../../hooks/useSmartAccountActivity";

const SMART_ACCOUNT_ADDRESS = "0x3333333333333333333333333333333333333333" as const;

function setupMocks({
  balanceValue = 1_000_000_000_000_000_000n,
  activities = [],
}: {
  balanceValue?: bigint;
  activities?: SmartAccountActivity[];
} = {}) {
  vi.mocked(useIdentity).mockReturnValue({
    username: "testuser",
    identityId: 1n,
    smartAccountAddress: SMART_ACCOUNT_ADDRESS,
  });

  vi.mocked(useBalance).mockReturnValue({
    data: { value: balanceValue },
    isLoading: false,
  } as ReturnType<typeof useBalance>);

  vi.mocked(useSmartAccountActivity).mockReturnValue({
    activities,
    isScanning: false,
    progress: null,
    error: null,
    rescan: vi.fn(),
  });

  vi.mocked(useAccount).mockReturnValue({ isConnected: true } as ReturnType<typeof useAccount>);
  vi.mocked(useWalletModal).mockReturnValue({ openConnectModal: vi.fn() });
  vi.mocked(useQueryClient).mockReturnValue({
    invalidateQueries: vi.fn(),
  } as unknown as ReturnType<typeof useQueryClient>);
  vi.mocked(useWriteContract).mockReturnValue({
    writeContract: vi.fn(),
    data: undefined,
    isPending: false,
    isError: false,
    error: null,
  } as ReturnType<typeof useWriteContract>);
  vi.mocked(useWaitForTransactionReceipt).mockReturnValue({
    isLoading: false,
    isSuccess: false,
  } as ReturnType<typeof useWaitForTransactionReceipt>);
}

describe("SmartAccountDashboard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the formatted balance", () => {
    setupMocks({ balanceValue: 1_500_000_000_000_000_000n });
    render(<SmartAccountDashboard />);

    expect(screen.getByText("1.5 ETH")).toBeInTheDocument();
  });

  it("shows the empty state when there is no activity", () => {
    setupMocks({ activities: [] });
    render(<SmartAccountDashboard />);

    expect(screen.getByText("No activity yet.")).toBeInTheDocument();
  });

  it("renders an activity entry with its type label", () => {
    setupMocks({
      activities: [
        {
          type: "session_created",
          hash: "0x1111111111111111111111111111111111111111111111111111111111111a",
          blockNumber: 100n,
          logIndex: 0,
          timestamp: 1_700_000_000,
          costWei: 21_000_000_000_000n,
        },
      ],
    });
    render(<SmartAccountDashboard />);

    expect(screen.getByText("Session created")).toBeInTheDocument();
  });

  it("tallies cost-by-type summary correctly", () => {
    setupMocks({
      balanceValue: 9_000_000_000_000_000_000n,
      activities: [
        {
          type: "session_created",
          hash: "0xaa1",
          blockNumber: 1n,
          logIndex: 0,
          timestamp: 1,
          costWei: 1_000_000_000_000_000_000n,
        },
        {
          type: "device_registered",
          hash: "0xbb1",
          blockNumber: 2n,
          logIndex: 0,
          timestamp: 2,
          costWei: 2_000_000_000_000_000_000n,
        },
      ],
    });
    render(<SmartAccountDashboard />);

    expect(screen.getByText("9 ETH")).toBeInTheDocument(); // balance
    expect(screen.getByText("1 ETH")).toBeInTheDocument(); // session bucket total
    expect(screen.getByText("2 ETH")).toBeInTheDocument(); // device bucket total
  });

  it("shows 'Not available yet' for vault when VaultRegistry is not deployed", () => {
    setupMocks();
    render(<SmartAccountDashboard />);

    expect(screen.getByText("Not available yet")).toBeInTheDocument();
  });

  it("opens the deposit modal when Deposit is clicked", async () => {
    setupMocks();
    render(<SmartAccountDashboard />);
    await userEvent.click(screen.getByRole("button", { name: "Deposit" }));

    expect(
      screen.getByText("Send ETH to your smart account address to fund future operations."),
    ).toBeInTheDocument();
  });

  it("opens the withdraw modal when Withdraw is clicked", async () => {
    setupMocks();
    render(<SmartAccountDashboard />);
    await userEvent.click(screen.getByRole("button", { name: "Withdraw" }));

    expect(screen.getByText("Destination address")).toBeInTheDocument();
  });
});
