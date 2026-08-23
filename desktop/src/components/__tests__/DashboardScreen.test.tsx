import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { DashboardScreen } from "../DashboardScreen";

vi.mock("../../contexts/IdentityContext", () => ({
  useIdentity: vi.fn(),
}));

vi.mock("../SmartAccountDashboard", () => ({
  SmartAccountDashboard: () => <div>eth-view</div>,
}));

vi.mock("../ArweaveDashboard", () => ({
  ArweaveDashboard: () => <div>arweave-view</div>,
}));

import { useIdentity } from "../../contexts/IdentityContext";

describe("DashboardScreen", () => {
  beforeEach(() => {
    vi.mocked(useIdentity).mockReturnValue({
      username: "testuser",
      identityId: 1n,
      smartAccountAddress: "0x3333333333333333333333333333333333333333",
    });
  });

  it("shows the ETH view by default", () => {
    render(<DashboardScreen />);
    expect(screen.getByText("eth-view")).toBeInTheDocument();
    expect(screen.queryByText("arweave-view")).not.toBeInTheDocument();
  });

  it("switches to the Arweave view on toggle click", async () => {
    render(<DashboardScreen />);
    await userEvent.click(screen.getByRole("button", { name: "Arweave" }));

    expect(screen.getByText("arweave-view")).toBeInTheDocument();
    expect(screen.queryByText("eth-view")).not.toBeInTheDocument();
  });

  it("switches back to the ETH view", async () => {
    render(<DashboardScreen />);
    await userEvent.click(screen.getByRole("button", { name: "Arweave" }));
    await userEvent.click(screen.getByRole("button", { name: "Ethereum" }));

    expect(screen.getByText("eth-view")).toBeInTheDocument();
  });
});
