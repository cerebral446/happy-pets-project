"""Build HappyPets.rbxlx (a Roblox place file) from the Luau sources in src/.

No Rojo needed: open the result in Roblox Studio with File -> Open from File.

Mapping (same as default.project.json):
  src/shared  -> ReplicatedStorage.Shared   (ModuleScripts)
  src/server  -> ServerScriptService         (*.server.luau = Script, else ModuleScript)
  src/client  -> StarterPlayer.StarterPlayerScripts (*.client.luau = LocalScript)

Usage: python3 tools/build_place.py [output.rbxlx]
"""
import itertools
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
_ids = itertools.count(1)


def ref():
    return f"RBX{next(_ids):08X}"


def cdata(text):
    # A literal "]]>" would end the CDATA section early; split it.
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def script_item(path: Path):
    name = path.name
    if name.endswith(".server.luau"):
        cls, inst = "Script", name[: -len(".server.luau")]
    elif name.endswith(".client.luau"):
        cls, inst = "LocalScript", name[: -len(".client.luau")]
    else:
        cls, inst = "ModuleScript", path.stem
    source = path.read_text(encoding="utf-8")
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(inst)}</string>'
        f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
        f"</Properties></Item>"
    )


def container(cls, name, children=""):
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(name)}</string>'
        f"</Properties>{children}</Item>"
    )


def scripts_in(folder: Path):
    return "".join(script_item(p) for p in sorted(folder.glob("*.luau")))


def audio_folders():
    """Empty Assets/Audio folders to drop Sounds into (see Config.Audio)."""
    config = (SRC / "shared" / "Config.luau").read_text(encoding="utf-8")
    species = re.findall(r'"(\w+)"', re.search(r"Config\.SpeciesOrder = \{([^}]*)\}", config).group(1))
    kinds = re.findall(r'"(\w+)"', re.search(r"PetKinds = \{([^}]*)\}", config).group(1))
    children = container("Folder", "Music")
    for sp in species:
        children += container("Folder", sp, "".join(container("Folder", k) for k in kinds))
    return container("Folder", "Assets", container("Folder", "Audio", children))


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "HappyPets.rbxlx"
    body = "".join(
        [
            # Streaming off: players have no avatar to stream around, and
            # visiting needs other players' homes on every client.
            (
                f'<Item class="Workspace" referent="{ref()}"><Properties>'
                '<string name="Name">Workspace</string>'
                '<bool name="StreamingEnabled">false</bool>'
                "</Properties></Item>"
            ),
            # Future lighting lets the lamps and window light glow softly.
            (
                f'<Item class="Lighting" referent="{ref()}"><Properties>'
                '<string name="Name">Lighting</string>'
                '<token name="Technology">4</token>'
                "</Properties></Item>"
            ),
            container(
                "ReplicatedStorage",
                "ReplicatedStorage",
                container("Folder", "Shared", scripts_in(SRC / "shared")) + audio_folders(),
            ),
            container("ServerScriptService", "ServerScriptService", scripts_in(SRC / "server")),
            container(
                "StarterPlayer",
                "StarterPlayer",
                container("StarterPlayerScripts", "StarterPlayerScripts", scripts_in(SRC / "client"))
                + container("StarterCharacterScripts", "StarterCharacterScripts"),
            ),
        ]
    )
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        f"{body}</roblox>\n"
    )
    out.write_text(xml, encoding="utf-8")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
