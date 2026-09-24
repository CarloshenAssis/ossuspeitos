"""Baixa o Godot oficial para o build do container (fase 8).

Usado só no estágio de build do Dockerfile. Baixa do release oficial no
GitHub, confere o SHA-512 publicado pelo projeto Godot (fixado no
Dockerfile) e extrai apenas os arquivos necessários:
  - o editor Linux x86_64 (para importar e exportar o projeto);
  - o template de release Linux x86_64 e o version.txt dos templates.

Sem dependências além da biblioteca padrão: respeita https_proxy do ambiente
e, se EXTRA_CA_PEM vier preenchida (proxy corporativo com CA própria), confia
nela além das CAs do sistema. Qualquer divergência de checksum aborta o build.
"""

import hashlib
import os
import shutil
import ssl
import sys
import tempfile
import urllib.request
import zipfile

RELEASES = "https://github.com/godotengine/godot/releases/download"


def ssl_context() -> ssl.SSLContext:
    context = ssl.create_default_context()
    extra = os.environ.get("EXTRA_CA_PEM", "").strip()
    if extra:
        context.load_verify_locations(cadata=extra)
    return context


def download(url: str, target: str, sha512: str, context: ssl.SSLContext) -> None:
    digest = hashlib.sha512()
    size = 0
    for attempt in range(1, 5):
        try:
            with urllib.request.urlopen(url, context=context, timeout=120) as response, open(target, "wb") as out:
                digest = hashlib.sha512()
                size = 0
                while True:
                    chunk = response.read(1 << 20)
                    if not chunk:
                        break
                    digest.update(chunk)
                    out.write(chunk)
                    size += len(chunk)
            break
        except OSError as error:
            print(f"FETCH_RETRY url={url} attempt={attempt} error={error}", flush=True)
            if attempt == 4:
                raise
    actual = digest.hexdigest()
    if actual != sha512:
        sys.exit(f"FETCH_CHECKSUM_MISMATCH url={url} expected={sha512} actual={actual}")
    print(f"FETCH_OK url={url} bytes={size} sha512={actual[:16]}...", flush=True)


def extract(archive: str, member: str, target: str, mode: int) -> None:
    with zipfile.ZipFile(archive) as bundle, bundle.open(member) as source, open(target, "wb") as out:
        shutil.copyfileobj(source, out)
    os.chmod(target, mode)


def main() -> None:
    version = os.environ["GODOT_VERSION"]
    editor_sha = os.environ["GODOT_EDITOR_SHA512"].lower()
    templates_sha = os.environ["GODOT_TEMPLATES_SHA512"].lower()
    editor_target = sys.argv[1]
    templates_dir = sys.argv[2]
    context = ssl_context()
    os.makedirs(templates_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as work:
        editor_zip = os.path.join(work, "editor.zip")
        download(f"{RELEASES}/{version}/Godot_v{version}_linux.x86_64.zip", editor_zip, editor_sha, context)
        extract(editor_zip, f"Godot_v{version}_linux.x86_64", editor_target, 0o755)
        os.remove(editor_zip)
        templates = os.path.join(work, "templates.tpz")
        download(f"{RELEASES}/{version}/Godot_v{version}_export_templates.tpz", templates, templates_sha, context)
        extract(templates, "templates/linux_release.x86_64", os.path.join(templates_dir, "linux_release.x86_64"), 0o755)
        extract(templates, "templates/version.txt", os.path.join(templates_dir, "version.txt"), 0o644)


if __name__ == "__main__":
    main()
