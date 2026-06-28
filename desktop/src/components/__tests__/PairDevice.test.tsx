import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { PairDevice } from "../PairDevice";

vi.mock("wagmi", () => ({
  useAccount: vi.fn(),
  useWriteContract: vi.fn(),
  useWaitForTransactionReceipt: vi.fn(),
}));

vi.mock("../../contexts/WalletModalContext", () => ({
  useWalletModal: vi.fn(),
}));

vi.mock("../../config/contracts", () => ({
  DEVICE_REGISTRY_ADDRESS: "0x0000000000000000000000000000000000000001",
  DEVICE_REGISTRY_ABI: [],
}));

import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { useWalletModal } from "../../contexts/WalletModalContext";

// Valid 40-hex Ethereum address (all lowercase passes isAddress)
const VALID_ADDRESS = "0x1111111111111111111111111111111111111111";

function setupMocks({
  isConnected = true,
  mockWriteContract = vi.fn(),
  mockOpenConnectModal = vi.fn(),
}: {
  isConnected?: boolean;
  mockWriteContract?: ReturnType<typeof vi.fn>;
  mockOpenConnectModal?: ReturnType<typeof vi.fn>;
} = {}) {
  vi.mocked(useAccount).mockReturnValue({
    // All-digit address: no checksum letters → always valid in EIP-55
    address: "0x2222222222222222222222222222222222222222" as `0x${string}`,
    isConnected,
  } as ReturnType<typeof useAccount>);

  vi.mocked(useWalletModal).mockReturnValue({
    openConnectModal: mockOpenConnectModal,
  });

  // Both useWriteContract() calls in PairDevice get the same mock
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

describe("PairDevice", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("shows the add-device button initially without the form", () => {
    setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);

    expect(screen.getByRole("button", { name: "+ Add device" })).toBeInTheDocument();
    expect(screen.queryByPlaceholderText("0x...")).not.toBeInTheDocument();
  });

  it("opens the form when the button is clicked", async () => {
    setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);

    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));

    expect(screen.getByPlaceholderText("0x...")).toBeInTheDocument();
    expect(screen.getByPlaceholderText("ex: iPhone 15 Pro")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Register device" })).toBeInTheDocument();
  });

  it("keeps Register device disabled when both fields are empty", async () => {
    setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));

    expect(screen.getByRole("button", { name: "Register device" })).toBeDisabled();
  });

  it("keeps Register device disabled when only label is filled", async () => {
    setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));
    await userEvent.type(screen.getByPlaceholderText("ex: iPhone 15 Pro"), "My Phone");

    expect(screen.getByRole("button", { name: "Register device" })).toBeDisabled();
  });

  it("shows invalid address error for a malformed address", async () => {
    setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));
    await userEvent.type(screen.getByPlaceholderText("0x..."), "not-an-address");

    expect(screen.getByText("Invalid address.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Register device" })).toBeDisabled();
  });

  it("enables Register device with a valid address and a label", async () => {
    setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));
    await userEvent.type(screen.getByPlaceholderText("0x..."), VALID_ADDRESS);
    await userEvent.type(screen.getByPlaceholderText("ex: iPhone 15 Pro"), "My Phone");

    expect(screen.getByRole("button", { name: "Register device" })).toBeEnabled();
  });

  it("closes the form when Cancel is clicked", async () => {
    setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));
    await userEvent.click(screen.getByRole("button", { name: "Cancel" }));

    expect(screen.queryByPlaceholderText("0x...")).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "+ Add device" })).toBeInTheDocument();
  });

  it("opens the wallet modal instead of registering when not connected", async () => {
    const { mockOpenConnectModal } = setupMocks({ isConnected: false });
    render(<PairDevice onDeviceRegistered={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));
    await userEvent.type(screen.getByPlaceholderText("0x..."), VALID_ADDRESS);
    await userEvent.type(screen.getByPlaceholderText("ex: iPhone 15 Pro"), "My Phone");
    await userEvent.click(screen.getByRole("button", { name: "Register device" }));

    expect(mockOpenConnectModal).toHaveBeenCalledOnce();
  });

  it("calls commitDevice on-chain when wallet is connected and inputs are valid", async () => {
    const { mockWriteContract } = setupMocks();
    render(<PairDevice onDeviceRegistered={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "+ Add device" }));
    await userEvent.type(screen.getByPlaceholderText("0x..."), VALID_ADDRESS);
    await userEvent.type(screen.getByPlaceholderText("ex: iPhone 15 Pro"), "My Phone");
    await userEvent.click(screen.getByRole("button", { name: "Register device" }));

    expect(mockWriteContract).toHaveBeenCalledWith(
      expect.objectContaining({ functionName: "commitDevice" })
    );
  });
});
