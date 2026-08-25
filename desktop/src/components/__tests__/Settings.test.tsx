import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Settings } from "../Settings";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

// MigrateWallet puxa ConnectWallet -> ConnectLedger/ConnectTrezor, que
// chamam `createConnector` real de wagmi no topo do módulo — mesmo motivo
// do stub em MigrateWallet.test.tsx/SmartAccountDashboard.test.tsx.
vi.mock("../MigrateWallet", () => ({
  MigrateWallet: () => <div data-testid="migrate-wallet-stub" />,
}));

import { invoke } from "@tauri-apps/api/core";

function setupInvoke(isEnabled: boolean) {
  vi.mocked(invoke).mockImplementation((cmd: string) => {
    if (cmd === "app_lock_is_enabled") return Promise.resolve(isEnabled);
    return Promise.resolve(undefined);
  });
}

describe("Settings", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the language and wallet sections", async () => {
    setupInvoke(false);
    render(<Settings onClose={vi.fn()} />);

    expect(screen.getByRole("combobox", { name: "Language" })).toBeInTheDocument();
    expect(await screen.findByTestId("migrate-wallet-stub")).toBeInTheDocument();
  });

  it("shows an Enable button when the app lock is off", async () => {
    setupInvoke(false);
    render(<Settings onClose={vi.fn()} />);

    expect(await screen.findByRole("button", { name: "Enable app lock" })).toBeInTheDocument();
  });

  it("shows a Disable button when the app lock is already on", async () => {
    setupInvoke(true);
    render(<Settings onClose={vi.fn()} />);

    expect(await screen.findByRole("button", { name: "Disable app lock" })).toBeInTheDocument();
  });

  it("keeps Enable disabled until password and confirmation match", async () => {
    setupInvoke(false);
    render(<Settings onClose={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "Enable app lock" }));

    await userEvent.type(screen.getByLabelText("New password"), "secret123");
    expect(screen.getByRole("button", { name: "Enable" })).toBeDisabled();

    await userEvent.type(screen.getByLabelText("Confirm password"), "secret123");
    expect(screen.getByRole("button", { name: "Enable" })).toBeEnabled();
  });

  it("calls app_lock_enable with the typed password", async () => {
    setupInvoke(false);
    render(<Settings onClose={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "Enable app lock" }));
    await userEvent.type(screen.getByLabelText("New password"), "secret123");
    await userEvent.type(screen.getByLabelText("Confirm password"), "secret123");
    await userEvent.click(screen.getByRole("button", { name: "Enable" }));

    expect(invoke).toHaveBeenCalledWith("app_lock_enable", { password: "secret123" });
  });

  it("calls app_lock_disable with the current password", async () => {
    setupInvoke(true);
    render(<Settings onClose={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "Disable app lock" }));
    await userEvent.type(screen.getByLabelText("Current password"), "secret123");
    await userEvent.click(screen.getByRole("button", { name: "Disable" }));

    expect(invoke).toHaveBeenCalledWith("app_lock_disable", { password: "secret123" });
  });

  it("shows the backend error when disabling with the wrong password", async () => {
    vi.mocked(invoke).mockImplementation((cmd: string) => {
      if (cmd === "app_lock_is_enabled") return Promise.resolve(true);
      if (cmd === "app_lock_disable") return Promise.reject(new Error("senha incorreta"));
      return Promise.resolve(undefined);
    });
    render(<Settings onClose={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "Disable app lock" }));
    await userEvent.type(screen.getByLabelText("Current password"), "wrong");
    await userEvent.click(screen.getByRole("button", { name: "Disable" }));

    expect(await screen.findByText(/senha incorreta/)).toBeInTheDocument();
  });
});
