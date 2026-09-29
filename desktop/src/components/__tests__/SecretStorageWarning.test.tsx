import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import "../../i18n";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

import { SecretStorageWarning } from "../SecretStorageWarning";

describe("SecretStorageWarning", () => {
  beforeEach(() => {
    invokeMock.mockReset();
  });

  it("shows the warning when secrets fell back to plain files", async () => {
    invokeMock.mockResolvedValue(true);
    render(<SecretStorageWarning />);
    await waitFor(() => expect(screen.getByRole("alert")).toBeTruthy());
    expect(invokeMock).toHaveBeenCalledWith("secret_storage_fallback_active");
  });

  it("renders nothing when the OS keyring is in use", async () => {
    invokeMock.mockResolvedValue(false);
    const { container } = render(<SecretStorageWarning />);
    await waitFor(() => expect(invokeMock).toHaveBeenCalled());
    expect(container.innerHTML).toBe("");
  });

  it("renders nothing if the check fails", async () => {
    invokeMock.mockRejectedValue("keyring_error");
    const { container } = render(<SecretStorageWarning />);
    await new Promise((r) => setTimeout(r, 20));
    expect(container.innerHTML).toBe("");
  });
});
