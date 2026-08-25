import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppLockGate } from "../AppLockGate";

describe("AppLockGate", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("keeps the unlock button disabled until a password is typed", () => {
    render(<AppLockGate onUnlock={vi.fn()} />);
    expect(screen.getByRole("button", { name: "Unlock" })).toBeDisabled();
  });

  it("calls onUnlock with the typed password", async () => {
    const mockUnlock = vi.fn().mockResolvedValue(true);
    render(<AppLockGate onUnlock={mockUnlock} />);

    await userEvent.type(screen.getByLabelText("Password"), "hunter2");
    await userEvent.click(screen.getByRole("button", { name: "Unlock" }));

    expect(mockUnlock).toHaveBeenCalledWith("hunter2");
  });

  it("shows an error and clears the field when the password is wrong", async () => {
    const mockUnlock = vi.fn().mockResolvedValue(false);
    render(<AppLockGate onUnlock={mockUnlock} />);

    await userEvent.type(screen.getByLabelText("Password"), "wrong");
    await userEvent.click(screen.getByRole("button", { name: "Unlock" }));

    expect(await screen.findByText("Wrong password.")).toBeInTheDocument();
    expect(screen.getByLabelText("Password")).toHaveValue("");
  });

  it("does not show an error after a correct password", async () => {
    const mockUnlock = vi.fn().mockResolvedValue(true);
    render(<AppLockGate onUnlock={mockUnlock} />);

    await userEvent.type(screen.getByLabelText("Password"), "correct");
    await userEvent.click(screen.getByRole("button", { name: "Unlock" }));

    expect(screen.queryByText("Wrong password.")).not.toBeInTheDocument();
  });
});
