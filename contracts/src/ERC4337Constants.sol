// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Endereco oficial do EntryPoint v0.7 (ERC-4337) — deployado via CREATE2 com
// salt zero, portanto identico em todas as EVM chains. Compartilhado entre
// scripts de deploy e testes para evitar divergencia se a versao mudar.
address constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
