import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("grant-togglemaster-iam.sh")
ACCOUNT = "123456789012"

MOCK_AWS = r"""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with open(os.environ["CALLS"], "a", encoding="utf-8") as calls:
    calls.write(json.dumps(args) + "\n")
if args[:1] == ["--profile"]:
    args = args[2:]
command = args[:2]
if command == ["configure", "get"]:
    print("us-west-2")
elif command == ["sts", "get-caller-identity"]:
    print("123456789012" if args[args.index("--query") + 1] == "Account"
          else "arn:aws:iam::123456789012:user/admin")
elif command == ["iam", "get-user"]:
    pass
elif command == ["iam", "get-policy"]:
    result = os.environ.get("POLICY_RESULT", "missing")
    if result == "missing":
        print("An error occurred (NoSuchEntity) when calling the GetPolicy operation", file=sys.stderr)
        sys.exit(1)
    if result == "denied":
        print("An error occurred (AccessDenied) when calling the GetPolicy operation", file=sys.stderr)
        sys.exit(1)
elif command == ["iam", "create-policy"]:
    document = args[args.index("--policy-document") + 1]
    Path(os.environ["DOCUMENT"]).write_text(Path(document.removeprefix("file://")).read_text())
    print("arn:aws:iam::123456789012:policy/ToggleMasterProjectProvisioner")
elif command == ["iam", "attach-user-policy"]:
    if os.environ.get("ATTACH_FAIL") == "1":
        print("AccessDenied", file=sys.stderr)
        sys.exit(1)
else:
    print(f"Unexpected AWS command: {args}", file=sys.stderr)
    sys.exit(2)
"""


class GrantIamTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        aws = self.directory / "aws"
        aws.write_text(MOCK_AWS)
        aws.chmod(0o755)
        self.calls_path = self.directory / "calls"
        self.document_path = self.directory / "policy.json"
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("AWS_")}
        self.env.update(
            PATH=f"{self.directory}{os.pathsep}{os.environ['PATH']}",
            CALLS=str(self.calls_path),
            DOCUMENT=str(self.document_path),
        )

    def run_script(self, confirmation="APPLY\n"):
        return subprocess.run(
            ["bash", str(SCRIPT), "togglemaster_user"],
            input=confirmation,
            text=True,
            capture_output=True,
            env=self.env,
            cwd=self.directory,
        )

    def calls(self):
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def test_create_combined_policy_with_session_region(self):
        self.env.update(AWS_PROFILE="lab", AWS_REGION="sa-east-1", AWS_DEFAULT_REGION="us-east-1")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertTrue(all(call[:2] == ["--profile", "lab"] for call in calls))
        self.assertFalse(any("configure" in call for call in calls))
        self.assertEqual(len([c for c in calls if "create-policy" in c]), 1)
        self.assertEqual(len([c for c in calls if "attach-user-policy" in c]), 1)
        text = self.document_path.read_text()
        self.assertLessEqual(len(text), 6144)
        self.assertNotIn("{{", text)
        statements = {s["Sid"]: s for s in json.loads(text)["Statement"]}
        self.assertEqual(
            statements["ManageProjectInfrastructureInSelectedRegion"]["Condition"]["StringEquals"]["aws:RequestedRegion"],
            "sa-east-1",
        )
        self.assertEqual(
            statements["ManageTerraformStateObjects"]["Resource"],
            f"arn:aws:s3:::togglemaster-tfstate-{ACCOUNT}/*",
        )
        self.assertEqual(statements["EcrLogin"]["Action"], "ecr:GetAuthorizationToken")
        self.assertEqual(set(statements["EcrPush"]["Action"]), {
            "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
            "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
        })
        self.assertNotIn("Condition", statements["EcrPush"])

    def test_profile_region_fallback_and_cancellation(self):
        result = self.run_script("no\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("us-west-2", result.stdout)
        self.assertTrue(any(c[:2] == ["configure", "get"] for c in self.calls()))
        self.assertFalse(any("create-policy" in c for c in self.calls()))

    def test_default_region_and_invalid_region(self):
        self.env["AWS_DEFAULT_REGION"] = "eu-west-1"
        result = self.run_script("no\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("eu-west-1", result.stdout)
        self.assertFalse(any("configure" in c for c in self.calls()))
        self.calls_path.unlink()
        self.env["AWS_REGION"] = "invalid"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("região AWS inválida", result.stderr)
        self.assertFalse(self.calls_path.exists())

    def test_existing_policy_and_lookup_failure_stop_creation(self):
        for policy_result in ("exists", "denied"):
            with self.subTest(policy_result=policy_result):
                self.calls_path.unlink(missing_ok=True)
                self.env["POLICY_RESULT"] = policy_result
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("já existe" if policy_result == "exists" else "AccessDenied", result.stderr)
                self.assertFalse(any("create-policy" in c for c in self.calls()))

    def test_failed_attachment_reports_created_policy(self):
        self.env["ATTACH_FAIL"] = "1"
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("foi criada, mas não foi anexada", result.stderr)
        self.assertTrue(self.document_path.exists())


if __name__ == "__main__":
    unittest.main()
