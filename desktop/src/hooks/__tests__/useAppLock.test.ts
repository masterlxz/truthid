import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import { useAppLock } from "../useAppLock";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

describe("useAppLock", () => {
  beforeEach(() => {
    invokeMock.mockReset();
  });

  it("starts as null (still checking), then resolves to the enabled state", async () => {
    invokeMock.mockResolvedValue(true);
    const { result } = renderHook(() => useAppLock());

    expect(result.current.isLocked).toBeNull();
    await waitFor(() => expect(result.current.isLocked).toBe(true));
  });

  it("treats app_lock_is_enabled errors as unlocked (fails open)", async () => {
    invokeMock.mockRejectedValue("boom");
    const { result } = renderHook(() => useAppLock());

    await waitFor(() => expect(result.current.isLocked).toBe(false));
  });

  it("unlock() sets isLocked false on a correct password", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "app_lock_is_enabled") return Promise.resolve(true);
      if (cmd === "app_lock_verify") return Promise.resolve(true);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    const { result } = renderHook(() => useAppLock());
    await waitFor(() => expect(result.current.isLocked).toBe(true));

    let correct: boolean | undefined;
    await act(async () => {
      correct = await result.current.unlock("hunter2");
    });

    expect(correct).toBe(true);
    expect(result.current.isLocked).toBe(false);
  });

  it("unlock() leaves isLocked true on a wrong password", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "app_lock_is_enabled") return Promise.resolve(true);
      if (cmd === "app_lock_verify") return Promise.resolve(false);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    const { result } = renderHook(() => useAppLock());
    await waitFor(() => expect(result.current.isLocked).toBe(true));

    await act(async () => {
      await result.current.unlock("wrong");
    });

    expect(result.current.isLocked).toBe(true);
  });

  it("unlock() propagates a rejection when app_lock_verify rejects (corrupted blob)", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "app_lock_is_enabled") return Promise.resolve(true);
      if (cmd === "app_lock_verify") return Promise.reject("hex decode error");
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    const { result } = renderHook(() => useAppLock());
    await waitFor(() => expect(result.current.isLocked).toBe(true));

    await expect(result.current.unlock("anything")).rejects.toBeTruthy();
  });

  it("reset() calls app_lock_reset and unlocks", async () => {
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "app_lock_is_enabled") return Promise.resolve(true);
      if (cmd === "app_lock_reset") return Promise.resolve(undefined);
      throw new Error(`unexpected invoke: ${cmd}`);
    });
    const { result } = renderHook(() => useAppLock());
    await waitFor(() => expect(result.current.isLocked).toBe(true));

    await act(async () => {
      await result.current.reset();
    });

    expect(invokeMock).toHaveBeenCalledWith("app_lock_reset");
    expect(result.current.isLocked).toBe(false);
  });
});
