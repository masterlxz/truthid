import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import { useLocalWalletBackupGate } from "../useLocalWalletBackupGate";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

describe("useLocalWalletBackupGate", () => {
  beforeEach(() => {
    invokeMock.mockReset();
  });

  it("starts as null (still checking), then resolves to false when there's no local wallet", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(false);
      if (cmd === "local_wallet_backup_confirmed") return Promise.resolve(false);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    const { result } = renderHook(() => useLocalWalletBackupGate());

    expect(result.current.needsBackup).toBeNull();
    await waitFor(() => expect(result.current.needsBackup).toBe(false));
  });

  it("needsBackup is true when a local wallet exists and the backup isn't confirmed yet", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(true);
      if (cmd === "local_wallet_backup_confirmed") return Promise.resolve(false);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    const { result } = renderHook(() => useLocalWalletBackupGate());

    await waitFor(() => expect(result.current.needsBackup).toBe(true));
  });

  it("needsBackup is false once the backup has been confirmed", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(true);
      if (cmd === "local_wallet_backup_confirmed") return Promise.resolve(true);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    const { result } = renderHook(() => useLocalWalletBackupGate());

    await waitFor(() => expect(result.current.needsBackup).toBe(false));
  });

  it("markConfirmed() re-runs the check", async () => {
    let confirmed = false;
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "local_wallet_exists") return Promise.resolve(true);
      if (cmd === "local_wallet_backup_confirmed") return Promise.resolve(confirmed);
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    const { result } = renderHook(() => useLocalWalletBackupGate());
    await waitFor(() => expect(result.current.needsBackup).toBe(true));

    confirmed = true;
    act(() => {
      result.current.markConfirmed();
    });

    await waitFor(() => expect(result.current.needsBackup).toBe(false));
  });

  it("treats invoke() errors as false (fails closed on the check, not stuck blocking)", async () => {
    invokeMock.mockRejectedValue("some_error");

    const { result } = renderHook(() => useLocalWalletBackupGate());

    await waitFor(() => expect(result.current.needsBackup).toBe(false));
  });
});
