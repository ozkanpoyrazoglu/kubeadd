import contextlib
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import kubeadd  # noqa: E402

EKS_ARN = "arn:aws:eks:eu-west-1:123456789012:cluster/{}"

SOURCE = """\
apiVersion: v1
kind: Config
clusters:
- name: {prod}
  cluster:
    server: https://prod.example.com
    certificate-authority-data: cHJvZA==
- name: {stage}
  cluster:
    server: https://stage.example.com:6443
users:
- name: {prod}
  user:
    token: prod-token
- name: {stage}
  user:
    token: stage-token
contexts:
- name: {prod}
  context: {{cluster: {prod}, user: {prod}}}
- name: {stage}
  context: {{cluster: {stage}, user: {stage}, namespace: apps}}
current-context: {prod}
""".format(prod=EKS_ARN.format("prod"), stage=EKS_ARN.format("stage"))

TARGET = """\
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    server: https://127.0.0.1:6443
users:
- name: local
  user:
    token: local-token
contexts:
- name: local
  context: {cluster: local, user: local}
current-context: local
"""


class HelperTests(unittest.TestCase):
    def test_parse_selection(self):
        names = ["a", "b", "c", "d"]
        self.assertEqual(kubeadd.parse_selection("2", names), [1])
        self.assertEqual(kubeadd.parse_selection("1, 3", names), [0, 2])
        self.assertEqual(kubeadd.parse_selection("2-4,2", names), [1, 2, 3])
        self.assertEqual(kubeadd.parse_selection("all", names), [0, 1, 2, 3])
        self.assertEqual(kubeadd.parse_selection("c 1", names), [2, 0])
        for bad in ("", "5", "0", "3-1", "x"):
            with self.assertRaises(ValueError):
                kubeadd.parse_selection(bad, names)

    def test_suggest_name(self):
        self.assertEqual(kubeadd.suggest_name(EKS_ARN.format("prod")), "prod")
        self.assertEqual(kubeadd.suggest_name("gke_my-project_europe-west1_main"), "main")
        self.assertEqual(kubeadd.suggest_name("kubernetes-admin@kubernetes"), "kubernetes-admin@kubernetes")

    def test_check_server_url(self):
        self.assertIsNone(kubeadd.check_server_url("https://k8s.example.com:6443"))
        self.assertIsNone(kubeadd.check_server_url("https://10.0.0.1/k8s/clusters/c-1"))
        self.assertIsNotNone(kubeadd.check_server_url("k8s.example.com"))
        self.assertIsNotNone(kubeadd.check_server_url("https://k8s.example.com:port"))
        self.assertIsNotNone(kubeadd.check_server_url(""))

    def test_prune_orphans_keeps_shared_entries(self):
        cfg = {
            "clusters": [{"name": "shared", "cluster": {}}, {"name": "solo", "cluster": {}}],
            "users": [{"name": "u", "user": {}}],
            "contexts": [{"name": "other", "context": {"cluster": "shared", "user": "u"}}],
        }
        removed = kubeadd.prune_orphans(cfg, ["shared", "solo"], ["u"])
        self.assertEqual(removed, [("cluster", "solo")])


class KubeconfigTestCase(unittest.TestCase):
    """Runs kubeadd against a temporary target kubeconfig."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        self.target = self._write("config", TARGET)

    def _write(self, name, text):
        path = os.path.join(self.tmp, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    def run_kubeadd(self, *args, answers=()):
        output = io.StringIO()
        with mock.patch("builtins.input", side_effect=list(answers)), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            code = kubeadd.main([*args, "--kubeconfig", self.target])
        return code, output.getvalue()

    def read_target(self):
        with open(self.target, encoding="utf-8") as handle:
            return handle.read()

    def target_cfg(self):
        return kubeadd.load_kubeconfig(self.target)

    def names(self, kind):
        return sorted(entry["name"] for entry in self.target_cfg()[kind + "s"])


@unittest.skipUnless(shutil.which("kubectl"), "kubectl is required")
class EndToEndTests(KubeconfigTestCase):
    def setUp(self):
        super().setUp()
        self.source = self._write("source.yaml", SOURCE)

    def test_requires_selection_when_non_interactive(self):
        code, output = self.run_kubeadd("-f", self.source, "-y")
        self.assertEqual(code, 1)
        self.assertIn("--context", output)

    def test_import_selected_context_with_custom_names(self):
        code, output = self.run_kubeadd(
            "-f", self.source, "-c", EKS_ARN.format("stage"), "-n", "stage",
            "--cluster-name", "stage-cluster", "--user-name", "stage-admin", "-y",
        )
        self.assertEqual(code, 0, output)
        cfg = self.target_cfg()
        self.assertEqual(kubeadd.find(cfg, "context", "stage")["context"],
                         {"cluster": "stage-cluster", "user": "stage-admin", "namespace": "apps"})
        self.assertEqual(kubeadd.find(cfg, "user", "stage-admin")["user"], {"token": "stage-token"})
        self.assertEqual(cfg["current-context"], "stage")
        self.assertTrue(any(name.startswith("config.backup.") for name in os.listdir(self.tmp)))

    def test_import_all_uses_short_names_and_keeps_current_context(self):
        code, output = self.run_kubeadd("-f", self.source, "--all", "-y")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.names("context"), ["local", "prod", "stage"])
        self.assertEqual(self.names("cluster"), ["local", "prod", "stage"])
        self.assertEqual(self.target_cfg()["current-context"], "local")

    def test_reimport_is_a_no_op(self):
        self.run_kubeadd("-f", self.source, "--all", "-y")
        code, output = self.run_kubeadd("-f", self.source, "--all", "-y")
        self.assertEqual(code, 0, output)
        self.assertIn("already up to date", output)

    def test_conflict_requires_overwrite(self):
        args = ("-f", self.source, "-c", EKS_ARN.format("prod"), "-n", "local", "-y")
        code, output = self.run_kubeadd(*args)
        self.assertEqual(code, 1)
        self.assertIn("--overwrite", output)
        code, output = self.run_kubeadd(*args, "--overwrite")
        self.assertEqual(code, 0, output)
        cluster = kubeadd.find(self.target_cfg(), "cluster", "local")
        self.assertEqual(cluster["cluster"]["server"], "https://prod.example.com")

    def test_interactive_multi_select_with_separate_names(self):
        answers = [
            "1,2",                                     # import both contexts
            "p", "y", "prod-cluster", "prod-user", "",  # prod: names, accept server
            "", "n", "n", "https://new.example.com",   # stage: default name, fix server
            "y", "2",                                  # switch to the second one
        ]
        code, output = self.run_kubeadd("-f", self.source, answers=answers)
        self.assertEqual(code, 0, output)
        cfg = self.target_cfg()
        self.assertEqual(kubeadd.find(cfg, "context", "p")["context"],
                         {"cluster": "prod-cluster", "user": "prod-user"})
        self.assertEqual(kubeadd.find(cfg, "cluster", "stage")["cluster"]["server"], "https://new.example.com")
        self.assertEqual(cfg["current-context"], "stage")

    def test_interactive_rename_on_conflict(self):
        # Renaming the context once also renames the cluster and user that follow it.
        answers = ["local", "n", "", "r", "local-2", "n"]
        code, output = self.run_kubeadd("-f", self.source, "-c", EKS_ARN.format("prod"), answers=answers)
        self.assertEqual(code, 0, output)
        self.assertEqual(self.names("context"), ["local", "local-2"])
        self.assertEqual(self.names("cluster"), ["local", "local-2"])
        self.assertEqual(self.names("user"), ["local", "local-2"])
        self.assertEqual(self.target_cfg()["current-context"], "local")

    def test_interactive_overwrite_asks_once(self):
        answers = ["local", "n", "", "o", "n"]
        code, output = self.run_kubeadd("-f", self.source, "-c", EKS_ARN.format("prod"), answers=answers)
        self.assertEqual(code, 0, output)
        self.assertEqual(output.count("already exists"), 1)
        cfg = self.target_cfg()
        self.assertEqual(kubeadd.find(cfg, "user", "local")["user"], {"token": "prod-token"})

    def test_dry_run_writes_nothing(self):
        before = self.read_target()
        code, output = self.run_kubeadd("-f", self.source, "--all", "-y", "--dry-run")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.read_target(), before)

    def test_delete_removes_unused_cluster_and_user(self):
        self.run_kubeadd("-f", self.source, "--all", "-y")
        code, output = self.run_kubeadd("-d", "prod", "-y")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.names("context"), ["local", "stage"])
        self.assertEqual(self.names("cluster"), ["local", "stage"])
        self.assertEqual(self.names("user"), ["local", "stage"])

    def test_interactive_delete_unsets_current_context(self):
        code, output = self.run_kubeadd("-d", answers=["1", "y"])
        self.assertEqual(code, 0, output)
        cfg = self.target_cfg()
        self.assertEqual(cfg["contexts"], [])
        self.assertEqual(cfg["current-context"], "")

    def test_list(self):
        code, output = self.run_kubeadd("-l")
        self.assertEqual(code, 0, output)
        self.assertIn("https://127.0.0.1:6443", output)



class FakeAws:
    """Stands in for the AWS CLI: lists clusters and writes update-kubeconfig output."""

    def __init__(self, clusters, profiles=("default",), region="eu-west-1", fail_regions=()):
        self.clusters = clusters  # {region: [names]}
        self.profiles = profiles
        self.region = region
        self.fail_regions = fail_regions
        self.calls = []

    def __call__(self, *args, profile=None, check=True):
        self.calls.append((args, profile))
        if args[:2] == ("configure", "list-profiles"):
            return "\n".join(self.profiles)
        if args[:3] == ("configure", "get", "region"):
            return self.region
        if args[:2] == ("ec2", "describe-regions"):
            return json.dumps(sorted(self.clusters))
        region = args[args.index("--region") + 1]
        if region in self.fail_regions:
            raise kubeadd.KubeaddError("aws eks failed: Token has expired")
        if args[:2] == ("eks", "list-clusters"):
            return json.dumps({"clusters": self.clusters.get(region, [])})
        if args[:2] == ("eks", "update-kubeconfig"):
            return self.update_kubeconfig(args, region, profile)
        raise AssertionError(f"unexpected aws call {args}")

    @staticmethod
    def update_kubeconfig(args, region, profile):
        name = args[args.index("--name") + 1]
        path = args[args.index("--kubeconfig") + 1]
        arn = f"arn:aws:eks:{region}:123456789012:cluster/{name}"
        token_args = ["--region", region, "eks", "get-token", "--cluster-name", name, "--output", "json"]
        if "--role-arn" in args:
            token_args += ["--role-arn", args[args.index("--role-arn") + 1]]
        user = {"exec": {"apiVersion": "client.authentication.k8s.io/v1beta1", "command": "aws", "args": token_args}}
        if profile:
            user["exec"]["env"] = [{"name": "AWS_PROFILE", "value": profile}]
        cfg = {"apiVersion": "v1", "kind": "Config", "clusters": [], "users": [], "contexts": []}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                cfg = json.load(handle)
        cfg["clusters"].append({"name": arn, "cluster": {"server": f"https://{name}.{region}.eks.amazonaws.com",
                                                          "certificate-authority-data": "Y2E="}})
        cfg["users"].append({"name": arn, "user": user})
        cfg["contexts"].append({"name": arn, "context": {"cluster": arn, "user": arn}})
        cfg["current-context"] = arn
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(cfg, handle)
        return f"Added new context {arn} to {path}"


@unittest.skipUnless(shutil.which("kubectl"), "kubectl is required")
class EksTests(KubeconfigTestCase):
    def setUp(self):
        super().setUp()
        environment = mock.patch.dict(os.environ)
        environment.start()
        self.addCleanup(environment.stop)
        for key in ("AWS_PROFILE", "AWS_REGION", "AWS_DEFAULT_REGION"):
            os.environ.pop(key, None)

    def run_eks(self, fake, *args, answers=()):
        with mock.patch.object(kubeadd, "aws", fake):
            return self.run_kubeadd("--eks", *args, answers=answers)

    def test_named_cluster_with_profile_and_name_format(self):
        fake = FakeAws({"eu-west-1": ["prod"]})
        code, output = self.run_eks(fake, "prod", "--profile", "acme", "--region", "eu-west-1",
                                    "--role-arn", "arn:aws:iam::123456789012:role/admin",
                                    "--name-format", "{profile}-{cluster}", "-y")
        self.assertEqual(code, 0, output)
        cfg = self.target_cfg()
        self.assertEqual(cfg["current-context"], "acme-prod")
        execution = kubeadd.find(cfg, "user", "acme-prod")["user"]["exec"]
        self.assertEqual(execution["env"], [{"name": "AWS_PROFILE", "value": "acme"}])
        self.assertIn("--role-arn", execution["args"])
        self.assertNotIn("list-clusters", [call[0][1] for call in fake.calls])

    def test_all_regions(self):
        fake = FakeAws({"eu-west-1": ["prod"], "us-east-1": ["prod", "dev"]})
        code, output = self.run_eks(fake, "--all-regions", "--all", "--name-format", "{cluster}-{region}", "-y")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.names("context"), ["dev-us-east-1", "local", "prod-eu-west-1", "prod-us-east-1"])
        self.assertEqual(self.target_cfg()["current-context"], "local")

    def test_same_cluster_name_in_two_regions_does_not_collide(self):
        fake = FakeAws({"eu-west-1": ["prod"], "us-east-1": ["prod"]})
        code, output = self.run_eks(fake, "prod", "--all-regions", "-y")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.names("context"),
                         ["arn:aws:eks:us-east-1:123456789012:cluster/prod", "local", "prod"])

    def test_interactive_profile_and_cluster_selection(self):
        fake = FakeAws({"eu-west-1": ["prod", "stage"]}, profiles=("default", "acme"))
        answers = [
            "2",           # profile: acme
            "2",           # cluster: stage
            "", "n",       # default context name, no separate cluster/user names
            "y",           # switch
        ]
        code, output = self.run_eks(fake, answers=answers)
        self.assertEqual(code, 0, output)
        self.assertEqual(self.target_cfg()["current-context"], "stage")
        self.assertIn((("eks", "list-clusters", "--region", "eu-west-1", "--output", "json"), "acme"), fake.calls)

    def test_expired_credentials_reported_once(self):
        fake = FakeAws({"eu-west-1": [], "us-east-1": []}, fail_regions=("eu-west-1", "us-east-1"))
        code, output = self.run_eks(fake, "--all-regions", "-y")
        self.assertEqual(code, 1)
        self.assertEqual(output.count("Token has expired"), 1)

    def test_requires_selection_when_non_interactive(self):
        fake = FakeAws({"eu-west-1": ["prod", "stage"]})
        code, output = self.run_eks(fake, "-y")
        self.assertEqual(code, 1)
        self.assertIn("--all", output)

    def test_invalid_name_format(self):
        code, output = self.run_eks(FakeAws({}), "--name-format", "{cluser}", "-y")
        self.assertEqual(code, 1)
        self.assertIn("placeholders", output)

    def test_eks_options_require_eks(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            kubeadd.main(["-l", "--region", "eu-west-1"])


if __name__ == "__main__":
    unittest.main()
