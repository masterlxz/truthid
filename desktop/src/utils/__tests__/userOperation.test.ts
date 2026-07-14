import { describe, expect, it } from "vitest";
import type { Address, Hex } from "viem";

import {
  ENTRY_POINT_V07,
  computeUserOperationHash,
  toPackedUserOperation,
  type UserOperationV07,
} from "../userOperation";

// Vetores idênticos aos de `mobile/test/utils/user_operation_test.dart`
// (gerados com `viem/account-abstraction` v2.52.2) — provam que a
// implementação TS bate byte a byte com a do Dart para o mesmo input, sem
// precisar de rede nem bundler de verdade.
describe("computeUserOperationHash — vetores conhecidos (viem v2.52.2)", () => {
  it("all_zero", () => {
    const op: UserOperationV07 = {
      sender: "0x0000000000000000000000000000000000000000" as Address,
      nonce: 0n,
      callData: "0x",
      callGasLimit: 0n,
      verificationGasLimit: 0n,
      preVerificationGas: 0n,
      maxFeePerGas: 0n,
      maxPriorityFeePerGas: 0n,
      signature: "0x",
    };

    const hash = computeUserOperationHash({
      userOperation: op,
      entryPoint: ENTRY_POINT_V07,
      chainId: 8453n,
    });

    expect(hash).toBe(
      "0xa7b74a3887217c32acb631306574bac263415b77bf91d0e1b9cfda7978dc3c7b",
    );
  });

  it("no_factory_no_paymaster", () => {
    const op: UserOperationV07 = {
      sender: "0x1234567890123456789012345678901234567890" as Address,
      nonce: 7n,
      callData: "0xabcdef01" as Hex,
      callGasLimit: 100000n,
      verificationGasLimit: 200000n,
      preVerificationGas: 50000n,
      maxFeePerGas: 1000000000n,
      maxPriorityFeePerGas: 100000000n,
      signature: "0x",
    };

    const hash = computeUserOperationHash({
      userOperation: op,
      entryPoint: ENTRY_POINT_V07,
      chainId: 8453n,
    });

    expect(hash).toBe(
      "0xae94190d47190ec9ce40f9a5e0f3aa9397208df172050e749446ced9072ba28b",
    );
  });

  it("with_factory", () => {
    const op: UserOperationV07 = {
      sender: "0xabCabCabcabcaBCAbCABCaBCabCabcabcabCabcA" as Address,
      nonce: 5n,
      factory: "0x1111111111111111111111111111111111111111" as Address,
      factoryData: "0xdeadbeef" as Hex,
      callData: "0x1234" as Hex,
      callGasLimit: 300000n,
      verificationGasLimit: 400000n,
      preVerificationGas: 60000n,
      maxFeePerGas: 2000000000n,
      maxPriorityFeePerGas: 150000000n,
      signature: "0x",
    };

    const hash = computeUserOperationHash({
      userOperation: op,
      entryPoint: ENTRY_POINT_V07,
      chainId: 84532n,
    });

    expect(hash).toBe(
      "0x6235da4b7e8f45cfcaa3e9c4873d8405bc576cfbdddc9492f7879200831e1c35",
    );
  });

  it("with_paymaster", () => {
    const op: UserOperationV07 = {
      sender: "0x9999999999999999999999999999999999999999" as Address,
      nonce: 42n,
      callData: "0xcafebabe" as Hex,
      callGasLimit: 150000n,
      verificationGasLimit: 250000n,
      preVerificationGas: 55000n,
      maxFeePerGas: 3000000000n,
      maxPriorityFeePerGas: 200000000n,
      paymaster: "0x2222222222222222222222222222222222222222" as Address,
      paymasterVerificationGasLimit: 80000n,
      paymasterPostOpGasLimit: 20000n,
      paymasterData: "0xfeedface" as Hex,
      signature: "0x",
    };

    const hash = computeUserOperationHash({
      userOperation: op,
      entryPoint: ENTRY_POINT_V07,
      chainId: 8453n,
    });

    expect(hash).toBe(
      "0x7bb0f3ed93d36190d8f134881b75b76e950f5b5aa1844bb5a65ece20e4f18b6f",
    );
  });

  it("large_values_with_signature", () => {
    const op: UserOperationV07 = {
      sender: "0x362dC9570CC35C7Fa04635167a891Df02445B7DB" as Address,
      nonce: 340282366920938463463374607431768211455n,
      callData:
        "0x1b11092d0000000000000000000000000000000000000000000000000000000000000001" as Hex,
      callGasLimit: 999999n,
      verificationGasLimit: 888888n,
      preVerificationGas: 77777n,
      maxFeePerGas: 123456789n,
      maxPriorityFeePerGas: 987654321n,
      signature: "0xaabbccddeeff" as Hex,
    };

    const hash = computeUserOperationHash({
      userOperation: op,
      entryPoint: ENTRY_POINT_V07,
      chainId: 84532n,
    });

    expect(hash).toBe(
      "0x0b705240177f10e7715c7f8234b5b0538f03dd55cea312f1f0d7b28fd1f8cc8e",
    );
  });
});

describe("toPackedUserOperation", () => {
  it("empacota accountGasLimits e gasFees em 32 bytes cada", () => {
    const op: UserOperationV07 = {
      sender: "0x1234567890123456789012345678901234567890" as Address,
      nonce: 0n,
      callData: "0x",
      callGasLimit: 0x1234n,
      verificationGasLimit: 0x5678n,
      preVerificationGas: 0n,
      maxFeePerGas: 0xabcdn,
      maxPriorityFeePerGas: 0x9n,
      signature: "0x",
    };

    const packed = toPackedUserOperation(op);

    // accountGasLimits = pad(verificationGasLimit, 16) ++ pad(callGasLimit, 16)
    expect(packed.accountGasLimits).toBe(
      `0x${"5678".padStart(32, "0")}${"1234".padStart(32, "0")}`,
    );
    // gasFees = pad(maxPriorityFeePerGas, 16) ++ pad(maxFeePerGas, 16)
    expect(packed.gasFees).toBe(`0x${"9".padStart(32, "0")}${"abcd".padStart(32, "0")}`);
  });

  it("sem factory gera initCode vazio; sem paymaster gera paymasterAndData vazio", () => {
    const op: UserOperationV07 = {
      sender: "0x1234567890123456789012345678901234567890" as Address,
      nonce: 0n,
      callData: "0x",
      callGasLimit: 0n,
      verificationGasLimit: 0n,
      preVerificationGas: 0n,
      maxFeePerGas: 0n,
      maxPriorityFeePerGas: 0n,
      signature: "0x",
    };

    const packed = toPackedUserOperation(op);

    expect(packed.initCode).toBe("0x");
    expect(packed.paymasterAndData).toBe("0x");
  });

  it("com factory, initCode é factory ++ factoryData", () => {
    const op: UserOperationV07 = {
      sender: "0x1234567890123456789012345678901234567890" as Address,
      nonce: 0n,
      factory: "0x1111111111111111111111111111111111111111" as Address,
      factoryData: "0xdeadbeef" as Hex,
      callData: "0x",
      callGasLimit: 0n,
      verificationGasLimit: 0n,
      preVerificationGas: 0n,
      maxFeePerGas: 0n,
      maxPriorityFeePerGas: 0n,
      signature: "0x",
    };

    const packed = toPackedUserOperation(op);

    expect(packed.initCode).toBe("0x1111111111111111111111111111111111111111deadbeef");
  });
});
