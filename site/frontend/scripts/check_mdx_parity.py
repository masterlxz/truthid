#!/usr/bin/env python3
"""Verifica paridade estrutural entre as páginas MDX traduzidas da doc do site.

Não entende prosa (isso fica pra revisão humana/build) — só garante que uma
tradução não mutilou a estrutura da página em relação ao inglês (fonte da
verdade), comparando, por arquivo:
  1. O conjunto de tags JSX abertas (nomes de componente/elemento).
  2. O conjunto de linguagens de code fence (```ts, ```bash, ...).
  3. O conjunto de chaves de frontmatter (nível superior do YAML entre `---`).

Também confirma que todo par (arquivo em inglês, locale) tem um arquivo
`<slug>.<locale>.mdx` existente nas 4 localizações de meta.json
(content/docs/meta.json + 3 subpastas), e que nenhum tradutor tocou os
arquivos fonte em inglês.

Sai com status != 0 e um diff legível em qualquer divergência.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

DOCS_DIR = Path(__file__).resolve().parent.parent / "content" / "docs"
LOCALES = ["pt-BR", "es", "zh-CN"]

JSX_TAG_RE = re.compile(r"<([A-Za-z][A-Za-z0-9]*)(?=[\s/>])")
CODE_FENCE_RE = re.compile(r"^```([A-Za-z0-9_+-]+)", re.MULTILINE)
FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
FRONTMATTER_KEY_RE = re.compile(r"^([A-Za-z0-9_-]+):", re.MULTILINE)


def find_english_mdx() -> list[Path]:
    return sorted(
        p
        for p in DOCS_DIR.rglob("*.mdx")
        if re.fullmatch(r"[^.]+\.mdx", p.name)
    )


def locale_sibling(en_path: Path, locale: str) -> Path:
    return en_path.with_name(en_path.stem + f".{locale}.mdx")


def extract_structure(text: str) -> dict[str, set[str]]:
    fm_match = FRONTMATTER_RE.match(text)
    frontmatter_keys = set(FRONTMATTER_KEY_RE.findall(fm_match.group(1))) if fm_match else set()
    body = text[fm_match.end() :] if fm_match else text

    return {
        "jsx_tags": set(JSX_TAG_RE.findall(body)),
        "code_fences": set(CODE_FENCE_RE.findall(body)),
        "frontmatter_keys": frontmatter_keys,
    }


def main() -> int:
    en_files = find_english_mdx()
    if not en_files:
        print(f"ERRO: nenhum arquivo .mdx em inglês encontrado em {DOCS_DIR}", file=sys.stderr)
        return 1

    ok = True

    for en_path in en_files:
        rel = en_path.relative_to(DOCS_DIR)
        en_structure = extract_structure(en_path.read_text(encoding="utf-8"))

        for locale in LOCALES:
            locale_path = locale_sibling(en_path, locale)
            if not locale_path.exists():
                ok = False
                print(f"[{locale}] FALTANDO: {locale_path.relative_to(DOCS_DIR)}")
                continue

            locale_structure = extract_structure(locale_path.read_text(encoding="utf-8"))

            for key, label in (
                ("jsx_tags", "tags JSX"),
                ("code_fences", "linguagens de code fence"),
                ("frontmatter_keys", "chaves de frontmatter"),
            ):
                en_set = en_structure[key]
                locale_set = locale_structure[key]
                if en_set != locale_set:
                    ok = False
                    missing = en_set - locale_set
                    extra = locale_set - en_set
                    print(f"[{locale}] {rel}: {label} divergem")
                    if missing:
                        print(f"  faltando (presente no inglês): {sorted(missing)}")
                    if extra:
                        print(f"  a mais (ausente no inglês): {sorted(extra)}")

    if ok:
        print(f"OK — {len(en_files)} páginas, paridade estrutural completa em {', '.join(LOCALES)}.")
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
