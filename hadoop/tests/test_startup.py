"""Exercise Makefile storage safeguards without accessing the Docker daemon."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
GIT_BASH = Path("C:/Program Files/Git/bin/bash.exe")
BASH = str(GIT_BASH) if os.name == "nt" and GIT_BASH.exists() else shutil.which("bash")


class StartupTests(unittest.TestCase):
    def run_target(self, target, states="", inventory_failure=False):
        with tempfile.TemporaryDirectory(prefix="bigdata-startup-test-") as directory:
            directory = Path(directory)
            log = directory / "docker.log"
            bootstrap = directory / "mock-docker.sh"
            bootstrap.write_text(
                """docker() {
    printf '%s\\n' "$*" >> "$DOCKER_TEST_LOG"
    case " $* " in
        *' ps --all '*)
            if [ "$DOCKER_TEST_FAIL" = 1 ]; then return 13; fi
            printf '%s\\n' "$DOCKER_TEST_STATES"
            ;;
    esac
    return 0
}
""",
                encoding="utf-8",
                newline="\n",
            )
            env = dict(os.environ, BASH_ENV=bootstrap.as_posix(),
                       DOCKER_TEST_LOG=log.as_posix(), DOCKER_TEST_STATES=states,
                       DOCKER_TEST_FAIL="1" if inventory_failure else "0")
            result = subprocess.run(
                ["make", "--no-print-directory", "-s", f"SHELL={BASH}", target],
                cwd=ROOT, env=env, text=True, capture_output=True, timeout=30,
            )
            commands = log.read_text().splitlines() if log.exists() else []
            return result, commands

    def test_routine_targets_never_initialize(self):
        for target in ("up", "normal-up", "all", "rebuild"):
            with self.subTest(target=target):
                result, commands = self.run_target(target)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(any("compose up -d" in c for c in commands))
                self.assertFalse(any("namenode-format" in c or " -format" in c for c in commands))

    def test_init_refuses_active_daemons(self):
        for state in ("running", "restarting", "paused", "dead", "exited\nrunning"):
            with self.subTest(state=state):
                result, commands = self.run_target("init", states=state)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any("run --rm namenode-format" in c for c in commands))

    def test_init_fails_closed_if_inventory_fails(self):
        result, commands = self.run_target("init", inventory_failure=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any("run --rm namenode-format" in c for c in commands))

    def test_init_accepts_only_absent_or_stopped_daemons(self):
        for state in ("", "created", "exited", "created\nexited"):
            with self.subTest(state=state):
                result, commands = self.run_target("init", states=state)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(any("run --rm namenode-format" in c for c in commands))
                self.assertFalse(any("compose up -d" in c for c in commands))

    def test_ci_initializes_before_starting_daemons(self):
        result, commands = self.run_target("ci-up")
        self.assertEqual(result.returncode, 0, result.stderr)
        initialization = next(i for i, c in enumerate(commands) if "run --rm namenode-format" in c)
        startup = next(i for i, c in enumerate(commands) if "compose up -d" in c)
        self.assertLess(initialization, startup)

    def test_compose_excludes_formatter_and_isolates_ci_volumes(self):
        for prefix in ("bigdata", "bigdata-ci-test"):
            for stack in ("hadoop", "pyspark"):
                with self.subTest(prefix=prefix, stack=stack):
                    result = subprocess.run(
                        ["docker", "compose", "-f", f"{stack}/docker-compose.yaml", "config", "--format", "json"],
                        cwd=ROOT, env=dict(os.environ, BIGDATA_VOLUME_PREFIX=prefix, COMPOSE_PROFILES=""),
                        text=True, capture_output=True, check=True, timeout=30,
                    )
                    config = json.loads(result.stdout)
                    self.assertNotIn("namenode-format", config["services"])
                    self.assertTrue(all(v["name"].startswith(prefix + "_") for v in config["volumes"].values()))


if __name__ == "__main__":
    if not BASH:
        raise SystemExit("Bash is required to test Makefile recipes.")
    unittest.main()
