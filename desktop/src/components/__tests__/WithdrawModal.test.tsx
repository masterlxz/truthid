import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { WithdrawModal } from "../WithdrawModal";

vi.mock("wagmi", () => ({
  useAccount: vi.fn(),
  useWriteContract: vi.fn(),
  useWaitForTransactionReceipt: vi.fn(),
}));

vi.mock("@tanstack/react-query", () => ({
  useQueryClient: vi.fn(),
}));

vi.mock("../../contexts/WalletModalContext", () => ({
  useWalletModal: vi.fn(),
}));

import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { useWalletModal } from "../../contexts/WalletModalContext";

const SMART_ACCOUNT_ADDRESS = "0x3333333333333333333333333333333333333333" as const;
const VALID_DESTINATION = "0x1111111111111111111111111111111111111111";
const AVAILABLE_BALANCE = 2_000_000_000_000_000_000n; // 2 ETH

function setupMocks({
  isConnected = true,
  mockWriteContract = vi.fn(),
  mockOpenConnectModal = vi.fn(),
}: {
  isConnected?: boolean;
  mockWriteContract?: ReturnType<typeof vi.fn>;
  mockOpenConnectModal?: ReturnType<typeof vi.fn>;
} = {}) {
  vi.mocked(useAccount).mockReturnValue({ isConnected } as ReturnType<typeof useAccount>);
  vi.mocked(useWalletModal).mockReturnValue({ openConnectModal: mockOpenConnectModal });
  vi.mocked(useQueryClient).mockReturnValue({
    invalidateQueries: vi.fn(),
  } as unknown as ReturnType<typeof useQueryClient>);
  vi.mocked(useWriteContract).mockReturnValue({
    writeContract: mockWriteContract,
    data: undefined,
    isPending: false,
    isError: false,
    error: null,
  } as ReturnType<typeof useWriteContract>);
  vi.mocked(useWaitForTransactionReceipt).mockReturnValue({
    isLoading: false,
    isSuccess: false,
  } as ReturnType<typeof useWaitForTransactionReceipt>);

  return { mockWriteContract, mockOpenConnectModal };
}

function renderModal() {
  return render(
    <WithdrawModal
      smartAccountAddress={SMART_ACCOUNT_ADDRESS}
      availableBalance={AVAILABLE_BALANCE}
      onClose={vi.fn()}
    />,
  );
}

describe("WithdrawModal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("shows invalid address error for a malformed address", async () => {
    setupMocks();
    renderModal();
    await userEvent.type(screen.getByPlaceholderText("0x..."), "not-an-address");

    expect(screen.getByText("Invalid address.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Withdraw" })).toBeDisabled();
  });

  it("shows an error and disables submit when amount exceeds available balance", async () => {
    setupMocks();
    renderModal();
    await userEvent.type(screen.getByPlaceholderText("0x..."), VALID_DESTINATION);
    await userEvent.type(screen.getByPlaceholderText("0.0"), "3");

    expect(screen.getByText("Amount exceeds available balance")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Withdraw" })).toBeDisabled();
  });

  it("fills the amount field with the full available balance when Max is clicked", async () => {
    setupMocks();
    renderModal();
    await userEvent.click(screen.getByRole("button", { name: "Max" }));

    expect(screen.getByPlaceholderText("0.0")).toHaveValue("2");
  });

  it("calls writeContract with execute(dest, value, '0x') for a valid withdrawal", async () => {
    const { mockWriteContract } = setupMocks();
    renderModal();
    await userEvent.type(screen.getByPlaceholderText("0x..."), VALID_DESTINATION);
    await userEvent.type(screen.getByPlaceholderText("0.0"), "1");
    await userEvent.click(screen.getByRole("button", { name: "Withdraw" }));

    expect(mockWriteContract).toHaveBeenCalledWith(
      expect.objectContaining({
        address: SMART_ACCOUNT_ADDRESS,
        functionName: "execute",
        args: [VALID_DESTINATION, 1_000_000_000_000_000_000n, "0x"],
      }),
    );
  });

  it("opens the wallet modal instead of withdrawing when not connected", async () => {
    const { mockOpenConnectModal, mockWriteContract } = setupMocks({ isConnected: false });
    renderModal();
    await userEvent.type(screen.getByPlaceholderText("0x..."), VALID_DESTINATION);
    await userEvent.type(screen.getByPlaceholderText("0.0"), "1");
    await userEvent.click(screen.getByRole("button", { name: "Withdraw" }));

    expect(mockOpenConnectModal).toHaveBeenCalledOnce();
    expect(mockWriteContract).not.toHaveBeenCalled();
  });
});
