import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor, act } from "@testing-library/react";
import { useUpdateCheck } from "../useUpdateCheck";

const checkMock = vi.fn();
const downloadAndInstallMock = vi.fn();
const relaunchMock = vi.fn();

vi.mock("@tauri-apps/plugin-updater", () => ({
  check: (...args: unknown[]) => checkMock(...args),
}));
vi.mock("@tauri-apps/plugin-process", () => ({
  relaunch: (...args: unknown[]) => relaunchMock(...args),
}));

describe("useUpdateCheck", () => {
  beforeEach(() => {
    checkMock.mockReset();
    downloadAndInstallMock.mockReset();
    relaunchMock.mockReset();
  });

  it("fica idle quando não há atualização disponível", async () => {
    checkMock.mockResolvedValue(null);
    const { result } = renderHook(() => useUpdateCheck());

    await waitFor(() => expect(checkMock).toHaveBeenCalled());
    expect(result.current.status).toBe("idle");
    expect(result.current.updateVersion).toBeNull();
  });

  it("vira available com a versão nova quando check() acha uma atualização", async () => {
    checkMock.mockResolvedValue({
      version: "2.2.0",
      downloadAndInstall: downloadAndInstallMock,
    });
    const { result } = renderHook(() => useUpdateCheck());

    await waitFor(() => expect(result.current.status).toBe("available"));
    expect(result.current.updateVersion).toBe("2.2.0");
  });

  it("falha silenciosa no check() — fica idle, sem lançar", async () => {
    checkMock.mockRejectedValue(new Error("network down"));
    const { result } = renderHook(() => useUpdateCheck());

    await waitFor(() => expect(checkMock).toHaveBeenCalled());
    expect(result.current.status).toBe("idle");
  });

  it("installUpdate() baixa+instala e vira ready, sem reiniciar sozinho", async () => {
    downloadAndInstallMock.mockResolvedValue(undefined);
    checkMock.mockResolvedValue({
      version: "2.2.0",
      downloadAndInstall: downloadAndInstallMock,
    });
    const { result } = renderHook(() => useUpdateCheck());
    await waitFor(() => expect(result.current.status).toBe("available"));

    await act(async () => {
      await result.current.installUpdate();
    });

    expect(downloadAndInstallMock).toHaveBeenCalledTimes(1);
    expect(result.current.status).toBe("ready");
    expect(relaunchMock).not.toHaveBeenCalled();
  });

  it("installUpdate() vira error se o download/instalação falhar", async () => {
    downloadAndInstallMock.mockRejectedValue(new Error("disk full"));
    checkMock.mockResolvedValue({
      version: "2.2.0",
      downloadAndInstall: downloadAndInstallMock,
    });
    const { result } = renderHook(() => useUpdateCheck());
    await waitFor(() => expect(result.current.status).toBe("available"));

    await act(async () => {
      await result.current.installUpdate();
    });

    expect(result.current.status).toBe("error");
  });

  it("restartNow() chama relaunch()", async () => {
    checkMock.mockResolvedValue(null);
    const { result } = renderHook(() => useUpdateCheck());
    await waitFor(() => expect(checkMock).toHaveBeenCalled());

    act(() => {
      result.current.restartNow();
    });

    expect(relaunchMock).toHaveBeenCalledTimes(1);
  });
});
