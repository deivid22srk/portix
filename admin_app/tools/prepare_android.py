#!/usr/bin/env python3
"""Ajusta o scaffold Android gerado para o app PORTIX ADM.

Adiciona a permissão de INTERNET, o rótulo e desativa o lintVital do AGP
(que quebra em alguns plugins). O `android/` não é versionado.
"""
import base64
import os
import re
from pathlib import Path


def patch_signing(android: Path) -> None:
    """Assinatura fixa do painel (mesma chave, applicationId diferente)."""
    encoded = os.environ.get("ANDROID_KEYSTORE_BASE64", "").strip()
    if not encoded:
        return

    app = android / "app"
    keystore = app / "portix-admin-release.p12"
    keystore.write_bytes(base64.b64decode(encoded))

    (android / "key.properties").write_text(
        (
            "storeFile={store}\n"
            "storePassword={store_pw}\n"
            "keyAlias={alias}\n"
            "keyPassword={key_pw}\n"
        ).format(
            store=keystore,
            store_pw=os.environ.get("ANDROID_KEYSTORE_PASSWORD", ""),
            alias=os.environ.get("ANDROID_KEY_ALIAS", "portix"),
            key_pw=os.environ.get("ANDROID_KEY_PASSWORD", ""),
        ),
        encoding="utf-8",
    )

    kts = app / "build.gradle.kts"
    groovy = app / "build.gradle"
    if kts.exists():
        text = kts.read_text(encoding="utf-8")
        if "keystoreProperties" not in text:
            loader = (
                "import java.io.FileInputStream\n"
                "import java.util.Properties\n\n"
                "val keystoreProperties = Properties()\n"
                'val keystorePropertiesFile = rootProject.file("key.properties")\n'
                "if (keystorePropertiesFile.exists()) {\n"
                "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
                "}\n\n"
            )
            signing = (
                "android {\n"
                "    signingConfigs {\n"
                '        create("release") {\n'
                '            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }\n'
                '            storePassword = keystoreProperties["storePassword"] as String?\n'
                '            keyAlias = keystoreProperties["keyAlias"] as String?\n'
                '            keyPassword = keystoreProperties["keyPassword"] as String?\n'
                "        }\n"
                "    }\n"
            )
            text = loader + text
            text = text.replace("android {", signing, 1)
            text = text.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = signingConfigs.getByName("release")',
            )
            kts.write_text(text, encoding="utf-8")
    elif groovy.exists():
        text = groovy.read_text(encoding="utf-8")
        if "keystoreProperties" not in text:
            loader = (
                "def keystoreProperties = new Properties()\n"
                'def keystorePropertiesFile = rootProject.file("key.properties")\n'
                "if (keystorePropertiesFile.exists()) {\n"
                "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
                "}\n\n"
            )
            signing = (
                "android {\n"
                "    signingConfigs {\n"
                "        release {\n"
                "            storeFile file(keystoreProperties['storeFile'])\n"
                "            storePassword keystoreProperties['storePassword']\n"
                "            keyAlias keystoreProperties['keyAlias']\n"
                "            keyPassword keystoreProperties['keyPassword']\n"
                "        }\n"
                "    }\n"
            )
            text = loader + text
            text = text.replace("android {", signing, 1)
            text = text.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
            groovy.write_text(text, encoding="utf-8")


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

    patch_signing(android)

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
