import { useState, useEffect, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useSignMessage } from "wagmi";
import { hexToSignature } from "viem";

const VAULT_KEY_MESSAGE = "TruthID Vault Key v1";

/**
 * Hook que gerencia a derivação da chave do vault a partir de uma assinatura
 * da wallet (RFC 6979 — determinística, mesma wallet + mesma mensagem = mesma
 * chave sempre).
 *
 * Estados possíveis:
 * - "loading"   — verificando se a chave já existe no keyring
 * - "ready"     — chave já derivada, vault está acessível
 * - "signing"   — wallet está assinando a mensagem
 * - "error"     — algo deu errado
 */
type VaultKeyState = "loading" | "ready" | "signing" | "error";

export function useVaultKey() {
  const [state, setState] = useState<VaultKeyState>("loading");
  const [error, setError] = useState<string | null>(null);

  const {
    signMessage,
    data: signature,
    isPending: signPending,
    isError: signError,
    error: signErr,
  } = useSignMessage();

  // Verifica se a chave já existe no keyring
  useEffect(() => {
    invoke<boolean>("vault_key_exists")
      .then((exists) => setState(exists ? "ready" : "ready"))
      .catch(() => {
        setState("ready");
      });
  }, []);

  // Quando a assinatura chega, deriva a chave e armazena no keyring
  useEffect(() => {
    if (!signature) return;

    try {
      const { r, s, v } = hexToSignature(signature);
      if (v == null) {
        setState("error");
        setError("Invalid signature: missing recovery id");
        return;
      }

      setState("signing");
      invoke("derive_vault_key_from_wallet", { r, s, v: Number(v) })
        .then(() => setState("ready"))
        .catch((e: string) => {
          setState("error");
          setError(String(e));
        });
    } catch (e) {
      setState("error");
      setError(String(e));
    }
  }, [signature]);

  // Dispara a assinatura da wallet
  const deriveKey = useCallback(() => {
    setError(null);
    setState("signing");
    signMessage({ message: VAULT_KEY_MESSAGE });
  }, [signMessage]);

  return { state, error, deriveKey, signPending, signError, signErr };
}