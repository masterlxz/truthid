#!/usr/bin/env python3
"""Verifica paridade entre os arquivos ARB de i18n do Mobile.

Carrega app_en.arb (base) + os locales traduzidos e garante:
  1. Todos compartilham exatamente o mesmo conjunto de chaves de tradução
     (ignorando "@@locale" e os blocos de metadata "@chave").
  2. Toda chave com "placeholders" declarados no bloco "@chave" do
     app_en.arb tem o mesmo conjunto de tokens "{nome}" presente no valor
     de cada locale traduzido.

Sai com status != 0 e um diff legível em qualquer divergência.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ARB_DIR = Path(__file__).resolve().parent.parent / "lib" / "l10n" / "arb"
BASE_LOCALE = "en"
TRANSLATED_LOCALES = ["pt_BR", "es", "zh_CN"]

PLACEHOLDER_RE = re.compile(r"\{(\w+)(?=[,}])", re.ASCII)


def load_arb(locale: str) -> dict:
    path = ARB_DIR / f"app_{locale}.arb"
    if not path.exists():
        print(f"ERRO: arquivo ausente: {path}", file=sys.stderr)
        sys.exit(1)
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def translation_keys(arb: dict) -> set[str]:
    return {k for k in arb if k != "@@locale" and not k.startswith("@")}


def placeholder_tokens(text: str) -> set[str]:
    return set(PLACEHOLDER_RE.findall(text))


def main() -> int:
    base = load_arb(BASE_LOCALE)
    base_keys = translation_keys(base)

    ok = True

    for locale in TRANSLATED_LOCALES:
        arb = load_arb(locale)
        keys = translation_keys(arb)

        missing = base_keys - keys
        extra = keys - base_keys
        if missing:
            ok = False
            print(f"[app_{locale}.arb] {len(missing)} chave(s) faltando:")
            for k in sorted(missing):
                print(f"  - {k}")
        if extra:
            ok = False
            print(f"[app_{locale}.arb] {len(extra)} chave(s) a mais (sem correspondente em app_en.arb):")
            for k in sorted(extra):
                print(f"  - {k}")

        for key in sorted(base_keys & keys):
            meta = base.get(f"@{key}")
            if not isinstance(meta, dict):
                continue
            declared_placeholders = set(meta.get("placeholders", {}).keys())
            if not declared_placeholders:
                continue

            base_tokens = placeholder_tokens(base[key])
            translated_tokens = placeholder_tokens(arb[key])

            if base_tokens != declared_placeholders:
                ok = False
                print(
                    f"[app_{BASE_LOCALE}.arb] chave '{key}': tokens no valor "
                    f"{sorted(base_tokens)} != placeholders declarados "
                    f"{sorted(declared_placeholders)}"
                )

            if translated_tokens != declared_placeholders:
                ok = False
                print(
                    f"[app_{locale}.arb] chave '{key}': tokens no valor "
                    f"traduzido {sorted(translated_tokens)} != placeholders "
                    f"declarados {sorted(declared_placeholders)}"
                )

    if ok:
        print(f"OK — {len(base_keys)} chaves, paridade completa entre "
              f"{BASE_LOCALE} e {', '.join(TRANSLATED_LOCALES)}.")
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
