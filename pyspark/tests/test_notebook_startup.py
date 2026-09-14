"""Exercise the Compose notebook settings against Linux-owned empty homes.

Requires the built image and Docker. Uses disposable tmpfs mounts, no project
data volumes, no published ports, and no network access.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]


def docker(*args, check=True):
    return subprocess.run(["docker", *args], check=check, text=True,
                          capture_output=True, timeout=30)


class NotebookStartupTests(unittest.TestCase):
    def test_foreign_owned_home_and_nonroot_server(self):
        # 1000 represents the default local user; 1001 represents a Linux
        # checkout owner. Both must work with an initially foreign-owned home.
        for uid, gid in ((1000, 100), (1001, 1001)):
            with self.subTest(uid=uid, gid=gid):
                config = subprocess.run(
                    ["docker", "compose", "-f", "pyspark/docker-compose.yaml",
                     "config", "--format", "json"], cwd=ROOT, check=True,
                    env=dict(os.environ, JUPYTER_UID=str(uid), JUPYTER_GID=str(gid)),
                    text=True, capture_output=True, timeout=30,
                )
                service = json.loads(config.stdout)["services"]["pyspark-notebook"]
                name = "bigdata-jupyter-test-" + uuid.uuid4().hex[:12]
                args = ["run", "-d", "--name", name, "--network", "none",
                        "--memory", str(service["mem_limit"]), "--cpus", str(service["cpus"]),
                        "--user", service["user"],
                        "--tmpfs", "/home/jovyan:uid=1002,gid=1002,mode=0755"]
                for key, value in service["environment"].items():
                    args.extend(["--env", f"{key}={value}"])
                args.append(service["image"])
                try:
                    docker(*args)
                    health = service["healthcheck"]["test"]
                    self.assertEqual(health[0], "CMD")
                    deadline = time.monotonic() + 90
                    while time.monotonic() < deadline:
                        state = json.loads(docker("inspect", "--format", "{{json .State}}", name).stdout)
                        self.assertTrue(state["Running"], f"Notebook exited: {state}")
                        if docker("exec", name, *health[1:], check=False).returncode == 0:
                            break
                        time.sleep(2)
                    else:
                        self.fail("Jupyter did not respond to its HTTP health check within 90 seconds")
                    # Assert the actual server dropped root after initialization.
                    processes = docker("exec", name, "ps", "-eo", "uid,args").stdout
                    server_uids = re.findall(r"^\s*(\d+)\s+.*?/jupyter-lab(?:\s|$)", processes, re.M)
                    self.assertEqual(server_uids, [str(uid)], processes)
                    docker("exec", "--user", f"{uid}:{gid}", name, "python", "-c",
                           "from pathlib import Path; "
                           "p=Path('/home/jovyan/workspace'); p.mkdir(exist_ok=True); "
                           "(p/'write-test.txt').write_text('notebook user can save'); "
                           "assert Path('/home/jovyan/.local/share/jupyter/runtime').is_dir()")
                finally:
                    docker("rm", "-f", name, check=False)


if __name__ == "__main__":
    unittest.main()
