import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MigrateWallet } from "../MigrateWallet";

vi.mock("wagmi", () => ({
  useAccount: vi.fn(),
  useBalance: vi.fn(),
  useDisconnect: vi.fn(),
  useReadContract: vi.fn(),
  useWriteContract: vi.fn(),
  useWaitForTransactionReceipt: vi.fn(),
}));

vi.mock("@tanstack/react-query", () => ({
  useQueryClient: vi.fn(),
}));

vi.mock("../../contexts/IdentityContext", () => ({
  useIdentity: vi.fn(),
}));

// Stub — ConnectWallet tem sua própria árvore de dependências de wagmi
// (useConnect, conectores de Ledger/Trezor/WalletConnect) que não faz
// sentido mockar aqui; MigrateWallet só precisa saber que ela existe nas
// fases "connectNew"/"connectOld".
vi.mock("../ConnectWallet", () => ({
  ConnectWallet: () => <div data-testid="connect-wallet-stub" />,
}));

// Fragmentos reais (não vazios) — MigrateWallet chama `encodeFunctionData`
// de verdade via `buildAccountCalls` (viem não é mockado), então o ABI
// mockado precisa bater com as funções usadas ou a codificação falha.
vi.mock("../../config/contracts", () => ({
  IDENTITY_REGISTRY_ADDRESS: "0x0000000000000000000000000000000000000001",
  IDENTITY_REGISTRY_ABI: [
    {
      type: "function",
      name: "transferController",
      inputs: [
        { name: "username", type: "string" },
        { name: "newController", type: "address" },
      ],
      outputs: [],
      stateMutability: "nonpayable",
    },
  ],
  FACTORY_ADDRESS: "0x0000000000000000000000000000000000000002",
  FACTORY_ABI: [
    {
      type: "function",
      name: "createAccount",
      inputs: [
        { name: "owner_", type: "address" },
        { name: "index", type: "uint256" },
      ],
      outputs: [{ name: "ret", type: "address" }],
      stateMutability: "nonpayable",
    },
    {
      type: "function",
      name: "getAddress",
      inputs: [
        { name: "owner_", type: "address" },
        { name: "index", type: "uint256" },
      ],
      outputs: [{ name: "", type: "address" }],
      stateMutability: "view",
    },
  ],
  TRUTHID_ACCOUNT_ABI: [
    {
      type: "function",
      name: "executeBatch",
      inputs: [
        { name: "dest", type: "address[]" },
        { name: "value", type: "uint256[]" },
        { name: "func", type: "bytes[]" },
      ],
      outputs: [],
      stateMutability: "nonpayable",
    },
  ],
}));

import {
  useAccount,
  useBalance,
  useDisconnect,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { useIdentity } from "../../contexts/IdentityContext";

const OLD_ACCOUNT = "0x3333333333333333333333333333333333333333" as const;
const NEW_OWNER = "0x4444444444444444444444444444444444444444" as const;
const NEW_ACCOUNT = "0x5555555555555555555555555555555555555555" as const;
const FACTORY_ADDRESS_FOR_TEST = "0x0000000000000000000000000000000000000002";
const IDENTITY_REGISTRY_ADDRESS_FOR_TEST = "0x0000000000000000000000000000000000000001";

function setupMocks({
  newOwnerConnected = false,
  oldBalanceWei = 1_000_000_000_000_000_000n, // 1 ETH
  mockWriteContract = vi.fn(),
  mockDisconnect = vi.fn(),
}: {
  newOwnerConnected?: boolean;
  oldBalanceWei?: bigint;
  mockWriteContract?: ReturnType<typeof vi.fn>;
  mockDisconnect?: ReturnType<typeof vi.fn>;
} = {}) {
  vi.mocked(useAccount).mockReturnValue({
    address: newOwnerConnected ? NEW_OWNER : undefined,
    isConnected: newOwnerConnected,
  } as ReturnType<typeof useAccount>);

  vi.mocked(useDisconnect).mockReturnValue({ disconnect: mockDisconnect } as ReturnType<typeof useDisconnect>);

  vi.mocked(useBalance).mockReturnValue({
    data: { value: oldBalanceWei },
  } as ReturnType<typeof useBalance>);

  vi.mocked(useReadContract).mockReturnValue({
    data: newOwnerConnected ? NEW_ACCOUNT : undefined,
  } as ReturnType<typeof useReadContract>);

  vi.mocked(useIdentity).mockReturnValue({
    username: "testuser",
    identityId: 1n,
    smartAccountAddress: OLD_ACCOUNT,
  });

  vi.mocked(useQueryClient).mockReturnValue({
    invalidateQueries: vi.fn(),
  } as unknown as ReturnType<typeof useQueryClient>);

  vi.mocked(useWriteContract).mockReturnValue({
    writeContract: mockWriteContract,
    data: undefined,
    isPending: false,
    isError: false,
    error: null,
    reset: vi.fn(),
  } as ReturnType<typeof useWriteContract>);

  vi.mocked(useWaitForTransactionReceipt).mockReturnValue({
    isLoading: false,
    isSuccess: false,
  } as ReturnType<typeof useWaitForTransactionReceipt>);

  return { mockWriteContract, mockDisconnect };
}

// Leva o componente até a fase "review" (nova wallet já capturada e
// confirmada, wallet antiga já "reconectada" via o mock de isConnected).
async function advanceToReview() {
  render(<MigrateWallet onClose={vi.fn()} />);
  await userEvent.click(screen.getByRole("button", { name: "Start" }));
  await userEvent.click(screen.getByRole("button", { name: "This is correct, continue" }));
}

describe("MigrateWallet", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("shows the intro screen first, with guardians/devices reassurance", () => {
    setupMocks({ newOwnerConnected: true });
    render(<MigrateWallet onClose={vi.fn()} />);

    expect(screen.getByText(/Migrate to another wallet/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Start" })).toBeInTheDocument();
  });

  it("captures the new wallet's address once connected and disconnects it", async () => {
    const { mockDisconnect } = setupMocks({ newOwnerConnected: true });
    render(<MigrateWallet onClose={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "Start" }));

    expect(screen.getByText(NEW_OWNER)).toBeInTheDocument();
    expect(screen.getByText(NEW_ACCOUNT)).toBeInTheDocument();
    expect(mockDisconnect).toHaveBeenCalledOnce();
  });

  it("blocks continuing when the predicted new account is the same as the current one", async () => {
    setupMocks({ newOwnerConnected: true });
    vi.mocked(useReadContract).mockReturnValue({
      data: OLD_ACCOUNT, // same as smartAccountAddress
    } as ReturnType<typeof useReadContract>);
    render(<MigrateWallet onClose={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "Start" }));

    expect(screen.getByText(/choose a different one/)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "This is correct, continue" })).toBeDisabled();
  });

  it("shows the old account balance in the review step", async () => {
    setupMocks({ newOwnerConnected: true, oldBalanceWei: 2_500_000_000_000_000_000n });
    await advanceToReview();

    expect(screen.getByText(/2.5 ETH/)).toBeInTheDocument();
  });

  it("submits a single executeBatch with createAccount + transferController + balance transfer", async () => {
    const { mockWriteContract } = setupMocks({ newOwnerConnected: true });
    await advanceToReview();
    await userEvent.click(screen.getByRole("button", { name: "Confirm migration" }));

    expect(mockWriteContract).toHaveBeenCalledWith(
      expect.objectContaining({
        address: OLD_ACCOUNT,
        functionName: "executeBatch",
        args: [
          [FACTORY_ADDRESS_FOR_TEST, IDENTITY_REGISTRY_ADDRESS_FOR_TEST, NEW_ACCOUNT],
          [0n, 0n, 1_000_000_000_000_000_000n],
          expect.arrayContaining([expect.any(String), expect.any(String), "0x"]),
        ],
      }),
    );
  });

  it("omits the balance-transfer call when the old account has zero balance", async () => {
    const { mockWriteContract } = setupMocks({ newOwnerConnected: true, oldBalanceWei: 0n });
    await advanceToReview();
    await userEvent.click(screen.getByRole("button", { name: "Confirm migration" }));

    const call = mockWriteContract.mock.calls[0][0];
    expect(call.args[0]).toHaveLength(2);
    expect(call.args[1]).toEqual([0n, 0n]);
  });
});
