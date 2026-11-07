"""Installer behavior on tiny fake installations only; never touches the live game."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


class InstallerTests(unittest.TestCase):
    def setUp(self):
        temporary = ROOT / ".tmp"
        temporary.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="installer-", dir=temporary)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        assert self.base.is_relative_to(temporary.resolve())
        self.package = self.base / "package with spaces"
        self.game = self.base / "Queen's Domain test"
        self.paks = self.game / "QueensDomain/Content/Paks"
        self.paks.mkdir(parents=True)
        self.package.mkdir()
        (self.game / "QueensDomain.exe").write_bytes(b"fixture executable")
        self.vanilla = self.paks / "QueensDomain-WindowsNoEditor.pak"
        self.vanilla.write_bytes(b"fixture vanilla resource")
        self.target = self.paks / "QueensDomain_Italian_P.pak"
        self.payload = b"fixture translated overlay"
        self.source = self.package / "QueensDomain/Content/Paks/QueensDomain_Italian_P.pak"
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(self.payload)
        shutil.copyfile(ROOT / "Gestisci-traduzione.ps1", self.package / "Gestisci-traduzione.ps1")
        self.manifest = {
            "overlay": {"filename": self.target.name, "sha256": sha(self.payload)},
            "compatible_vanilla_paks": [{"game_version": "fixture", "sha256": sha(self.vanilla.read_bytes())}],
        }
        self.write_manifest()
        self.env = os.environ.copy()
        self.env.update(TMP=str(self.base), TEMP=str(self.base))

    def write_manifest(self):
        (self.package / "mod.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def run_installer(self, action="Install", running=False, extra="", answer=None):
        """answer=None runs the script with -NonInteractive; otherwise it is piped to the confirmation prompt."""
        literal = lambda text: "'" + str(text).replace("'", "''") + "'"
        process = "[pscustomobject]@{ProcessName='QueensDomain-Win64-Shipping'}" if running else "@()"
        command = (
            "function Get-Process { " + process + " }; & "
            + literal(self.package / "Gestisci-traduzione.ps1")
            + " -Action " + action + " -GamePath " + literal(self.game)
            + ("" if answer is not None else " -NonInteractive") + extra
        )
        flags = ["-NoLogo", "-NoProfile"] + ([] if answer is not None else ["-NonInteractive"])
        result = subprocess.run(
            ["powershell.exe", *flags, "-ExecutionPolicy", "Bypass", "-Command", command],
            capture_output=True, encoding="utf-8", errors="replace", env=self.env, timeout=30,
            input=answer,
        )
        self.assertEqual(self.vanilla.read_bytes(), b"fixture vanilla resource")
        self.assertFalse(list(self.paks.glob("*.tmp")))
        return result

    def test_installs_exact_payload_and_preserves_original(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertEqual(len(list(self.paks.iterdir())), 2)

    def test_already_installed_is_idempotent(self):
        self.target.write_bytes(self.payload)
        before = self.target.stat().st_mtime_ns
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.target.stat().st_mtime_ns, before)

    def test_different_overlay_is_never_overwritten(self):
        self.target.write_bytes(b"another mod or edited translation")
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertEqual(self.target.read_bytes(), b"another mod or edited translation")

    def unknown_vanilla(self):
        self.manifest["compatible_vanilla_paks"][0]["sha256"] = "0" * 64
        self.write_manifest()

    def test_unknown_vanilla_needs_confirmation_when_non_interactive(self):
        self.unknown_vanilla()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AccettaVersioneNonVerificata", result.stdout)
        self.assertFalse(self.target.exists())

    def test_unknown_vanilla_installs_with_explicit_switch_and_warns(self):
        self.unknown_vanilla()
        result = self.run_installer(extra=" -AccettaVersioneNonVerificata")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ATTENZIONE", result.stdout)
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertEqual(len(list(self.paks.iterdir())), 2)

    def test_unknown_vanilla_interactive_yes_installs(self):
        self.unknown_vanilla()
        result = self.run_installer(answer="s\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_unknown_vanilla_interactive_no_or_empty_cancels(self):
        self.unknown_vanilla()
        for answer in ("n\n", "\n", ""):
            result = self.run_installer(answer=answer)
            self.assertNotEqual(result.returncode, 0, answer)
            self.assertFalse(self.target.exists(), answer)

    def test_unknown_vanilla_never_overwrites_another_overlay(self):
        self.unknown_vanilla()
        self.target.write_bytes(b"another mod or edited translation")
        self.assertNotEqual(self.run_installer(extra=" -AccettaVersioneNonVerificata").returncode, 0)
        self.assertEqual(self.target.read_bytes(), b"another mod or edited translation")

    def test_duplicate_compatible_entries_are_rejected(self):
        self.manifest["compatible_vanilla_paks"].append(dict(self.manifest["compatible_vanilla_paks"][0]))
        self.write_manifest()
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertFalse(self.target.exists())

    def test_corrupt_download_is_rejected(self):
        self.source.write_bytes(b"broken payload")
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertFalse(self.target.exists())

    def test_running_game_blocks_install_and_removal(self):
        self.assertNotEqual(self.run_installer(running=True).returncode, 0)
        self.assertFalse(self.target.exists())
        self.target.write_bytes(self.payload)
        self.assertNotEqual(self.run_installer("Uninstall", running=True).returncode, 0)
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_uninstall_after_game_update_removes_only_exact_mod(self):
        self.target.write_bytes(self.payload)
        self.manifest["compatible_vanilla_paks"][0]["sha256"] = "0" * 64
        self.write_manifest()
        result = self.run_installer("Uninstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.paks.iterdir()), [self.vanilla])

    def test_changed_overlay_is_preserved_on_uninstall(self):
        self.target.write_bytes(b"externally changed overlay")
        self.assertNotEqual(self.run_installer("Uninstall").returncode, 0)
        self.assertEqual(self.target.read_bytes(), b"externally changed overlay")

    def test_absent_mod_uninstall_is_idempotent(self):
        result = self.run_installer("Uninstall")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.target.exists())


if __name__ == "__main__":
    unittest.main()
