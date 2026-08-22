import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { BitwardenImport } from "../BitwardenImport";

const invokeMock = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invokeMock(...args),
}));

const openMock = vi.fn();
vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: (...args: unknown[]) => openMock(...args),
}));

const readFileMock = vi.fn();
vi.mock("@tauri-apps/plugin-fs", () => ({
  readFile: (...args: unknown[]) => readFileMock(...args),
}));

function jsonBytes(value: unknown): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(value));
}

const NEW_LOGIN = {
  id: "",
  site: "GitHub",
  url: "https://github.com",
  username: "alice",
  password: "hunter2",
  notes: "",
  profiles: [],
  favorite: false,
  type: "credential",
  created_at: 0,
  updated_at: 0,
  possible_duplicate_id: null,
};

const DUPLICATE_LOGIN = {
  id: "",
  site: "Gmail",
  url: "https://gmail.com",
  username: "bob",
  password: "x",
  notes: "",
  profiles: [],
  favorite: false,
  type: "credential",
  created_at: 0,
  updated_at: 0,
  possible_duplicate_id: "existing-entry-id",
};

describe("BitwardenImport", () => {
  beforeEach(() => {
    invokeMock.mockReset();
    openMock.mockReset();
    readFileMock.mockReset();
  });

  it("picks an unencrypted export, previews it, and defaults a duplicate row to skip", async () => {
    openMock.mockResolvedValue("/tmp/export.json");
    readFileMock.mockResolvedValue(jsonBytes({ encrypted: false, items: [] }));
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "bitwarden_parse_export") {
        return Promise.resolve({ candidates: [NEW_LOGIN, DUPLICATE_LOGIN], skipped: [] });
      }
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    const onImported = vi.fn();
    render(<BitwardenImport onImported={onImported} />);
    await userEvent.click(screen.getByRole("button", { name: /choose export file/i }));

    await waitFor(() => expect(screen.getByText("GitHub")).toBeInTheDocument());
    expect(screen.getByText("Gmail")).toBeInTheDocument();

    // Só a linha da duplicata tem o seletor de ação, e o padrão é "pular".
    const select = screen.getByRole("combobox") as HTMLSelectElement;
    expect(select.value).toBe("skip");
  });

  it("writes new entries and overwritten duplicates, but never a skipped duplicate", async () => {
    openMock.mockResolvedValue("/tmp/export.json");
    readFileMock.mockResolvedValue(jsonBytes({ encrypted: false, items: [] }));
    invokeMock.mockImplementation((cmd: string, args?: Record<string, unknown>) => {
      if (cmd === "bitwarden_parse_export") {
        return Promise.resolve({ candidates: [NEW_LOGIN, DUPLICATE_LOGIN], skipped: [] });
      }
      if (cmd === "vault_upsert_entry") {
        return Promise.resolve(args?.entry);
      }
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    const onImported = vi.fn();
    render(<BitwardenImport onImported={onImported} />);
    await userEvent.click(screen.getByRole("button", { name: /choose export file/i }));
    await waitFor(() => expect(screen.getByText("GitHub")).toBeInTheDocument());

    // Confirma com o padrão (duplicata em "pular") — só a entrada nova deve
    // ser gravada.
    await userEvent.click(screen.getByRole("button", { name: /^import 1 item$/i }));

    await waitFor(() => expect(onImported).toHaveBeenCalledTimes(1));
    const upsertCalls = invokeMock.mock.calls.filter(([cmd]) => cmd === "vault_upsert_entry");
    expect(upsertCalls).toHaveLength(1);
    expect(upsertCalls[0][1]).toEqual({ entry: expect.objectContaining({ site: "GitHub", id: "" }) });
  });

  it("uses the existing id when a duplicate is set to overwrite", async () => {
    openMock.mockResolvedValue("/tmp/export.json");
    readFileMock.mockResolvedValue(jsonBytes({ encrypted: false, items: [] }));
    invokeMock.mockImplementation((cmd: string, args?: Record<string, unknown>) => {
      if (cmd === "bitwarden_parse_export") {
        return Promise.resolve({ candidates: [DUPLICATE_LOGIN], skipped: [] });
      }
      if (cmd === "vault_upsert_entry") {
        return Promise.resolve(args?.entry);
      }
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<BitwardenImport onImported={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: /choose export file/i }));
    await waitFor(() => expect(screen.getByText("Gmail")).toBeInTheDocument());

    await userEvent.selectOptions(screen.getByRole("combobox"), "overwrite");
    await userEvent.click(screen.getByRole("button", { name: /^import 1 item$/i }));

    await waitFor(() => {
      const upsertCalls = invokeMock.mock.calls.filter(([cmd]) => cmd === "vault_upsert_entry");
      expect(upsertCalls).toHaveLength(1);
      expect(upsertCalls[0][1]).toEqual({
        entry: expect.objectContaining({ site: "Gmail", id: "existing-entry-id" }),
      });
    });
  });

  it("prompts for a password on a password-protected export and retries after a wrong password", async () => {
    openMock.mockResolvedValue("/tmp/export.json");
    readFileMock.mockResolvedValue(
      jsonBytes({ encrypted: true, passwordProtected: true, salt: "s", kdfIterations: 1, kdfType: 0, encKeyValidation_DO_NOT_EDIT: "x", data: "y" }),
    );
    invokeMock.mockImplementation((cmd: string) => {
      if (cmd === "bitwarden_decrypt_export") {
        return Promise.reject("senha do export incorreta");
      }
      throw new Error(`unexpected invoke: ${cmd}`);
    });

    render(<BitwardenImport onImported={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: /choose export file/i }));

    await waitFor(() => expect(screen.getByLabelText(/password/i)).toBeInTheDocument());
    await userEvent.type(screen.getByLabelText(/password/i), "wrong");
    await userEvent.click(screen.getByRole("button", { name: /unlock/i }));

    await waitFor(() => expect(screen.getByText("senha do export incorreta")).toBeInTheDocument());
    // Ainda na tela de senha — não voltou pra escolher o arquivo de novo.
    expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
  });
});
