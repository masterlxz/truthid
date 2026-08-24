import { describe, it, expect, vi, beforeEach } from "vitest";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

// Importado depois do mock — trezor.ts chama invoke() no momento da assinatura,
// não no import, mas seguimos a mesma convenção dos outros testes do projeto.
const { trezor, setTrezorAccountIndex } = await import("../trezor");

const CHAIN = { id: 8453, rpcUrls: { default: { http: ["https://mainnet.base.org"] } } } as never;
const ADDRESS = "0x1234567890123456789012345678901234567890";

function makeInstance(emit: (...args: unknown[]) => void = vi.fn()) {
  return trezor({
    chains: [CHAIN],
    emitter: { emit, on: vi.fn(), off: vi.fn() } as never,
    transports: {},
  } as never);
}

describe("trezor connector", () => {
  beforeEach(async () => {
    invokeMock.mockReset();
    setTrezorAccountIndex(0);
    // `cachedAddress` é estado a nível de módulo — desconecta antes de cada
    // teste pra nenhum teste anterior vazar um endereço "conectado" pro próximo.
    await makeInstance().disconnect!();
  });

  it("has the expected connector id/type", () => {
    const instance = makeInstance();
    expect(instance.id).toBe("trezor");
    expect(instance.type).toBe("trezor");
    expect(instance.name).toBe("Trezor");
  });

  it("isAuthorized() is always false — never auto-reconnects without replugging the device", async () => {
    await expect(makeInstance().isAuthorized!()).resolves.toBe(false);
  });

  it("getAccounts throws a plain Error when not connected", async () => {
    await expect(makeInstance().getAccounts!()).rejects.toThrow("Trezor not connected.");
  });

  it("connect() invokes get_trezor_address with the cached account index and normalizes the address", async () => {
    invokeMock.mockResolvedValueOnce(ADDRESS);
    const emit = vi.fn();
    const instance = makeInstance(emit);

    setTrezorAccountIndex(2);
    const result = await instance.connect!({ chainId: 8453 } as never);

    expect(invokeMock).toHaveBeenCalledWith("get_trezor_address", { accountIndex: 2 });
    expect((result as { accounts: readonly string[] }).accounts[0].toLowerCase()).toBe(ADDRESS);
    expect(emit).toHaveBeenCalledWith("connect", expect.objectContaining({ chainId: 8453 }));

    await expect(instance.getAccounts!()).resolves.toEqual([expect.stringMatching(/^0x/)]);
  });

  it("provider dispatches eth_chainId/eth_accounts without touching invoke()", async () => {
    invokeMock.mockResolvedValueOnce(ADDRESS); // connect()
    const instance = makeInstance();
    await instance.connect!({ chainId: 8453 } as never);
    invokeMock.mockReset();

    const provider = (await instance.getProvider!({ chainId: 8453 })) as {
      request: (args: { method: string; params?: readonly unknown[] }) => Promise<unknown>;
    };

    await expect(provider.request({ method: "eth_chainId" })).resolves.toBe("0x2105"); // 8453
    await expect(provider.request({ method: "eth_accounts" })).resolves.toEqual([
      expect.stringMatching(/^0x/),
    ]);
    expect(invokeMock).not.toHaveBeenCalled();
  });

  it("provider wraps a plain-string rejection from invoke() into a real Error (personal_sign)", async () => {
    invokeMock.mockResolvedValueOnce(ADDRESS); // connect()
    const instance = makeInstance();
    await instance.connect!({ chainId: 8453 } as never);

    invokeMock.mockRejectedValueOnce("rejected_by_user"); // sign_trezor_personal_message
    const provider = (await instance.getProvider!({ chainId: 8453 })) as {
      request: (args: { method: string; params?: readonly unknown[] }) => Promise<unknown>;
    };

    await expect(
      provider.request({ method: "personal_sign", params: ["0xdeadbeef"] }),
    ).rejects.toBeInstanceOf(Error);
  });

  it("personal_sign forwards the message hex and cached account index to sign_trezor_personal_message", async () => {
    invokeMock.mockResolvedValueOnce(ADDRESS); // connect()
    const instance = makeInstance();
    setTrezorAccountIndex(1);
    await instance.connect!({ chainId: 8453 } as never);

    invokeMock.mockResolvedValueOnce("0xsignature");
    const provider = (await instance.getProvider!({ chainId: 8453 })) as {
      request: (args: { method: string; params?: readonly unknown[] }) => Promise<unknown>;
    };

    const result = await provider.request({ method: "personal_sign", params: ["0xdeadbeef", ADDRESS] });

    expect(result).toBe("0xsignature");
    expect(invokeMock).toHaveBeenCalledWith("sign_trezor_personal_message", {
      messageHex: "0xdeadbeef",
      accountIndex: 1,
    });
  });
});
