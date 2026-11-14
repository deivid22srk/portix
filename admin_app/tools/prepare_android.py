#!/usr/bin/env python3
"""Ajusta o scaffold Android gerado para o app PORTIX ADM.

Adiciona a permissão de INTERNET, o rótulo e desativa o lintVital do AGP
(que quebra em alguns plugins). O `android/` não é versionado.
"""
from __future__ import annotations

import re
from pathlib import Path


def main() -> None:
    android = Path(__file__).resolve().parents[1] / "android"
    if not android.exists():
        raise SystemExit("Pasta android/ ausente: rode flutter create antes")

    manifest = android / "app" / "src" / "main" / "AndroidManifest.xml"
    text = manifest.read_text(encoding="utf-8")

    if "android.permission.INTERNET" not in text:
        text = re.sub(
            r"(<manifest[^>]*>)",
            r'\1\n    <uses-permission android:name="android.permission.INTERNET" />',
            text,
            count=1,
        )
    text = re.sub(r'android:label="[^"]*"', 'android:label="PORTIX ADM"', text, count=1)
    manifest.write_text(text, encoding="utf-8")

    root_kts = android / "build.gradle.kts"
    root_groovy = android / "build.gradle"
    root = root_kts if root_kts.exists() else root_groovy
    if root.exists():
        content = root.read_text(encoding="utf-8")
        if "lintVital" not in content:
            content += (
                "\nsubprojects {\n"
                '    tasks.matching { it.name.startsWith("lintVital") }.configureEach {\n'
                "        enabled = false\n"
                "    }\n"
                "}\n"
            )
            root.write_text(content, encoding="utf-8")

    print("Scaffold do painel ajustado.")


if __name__ == "__main__":
    main()
