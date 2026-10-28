# kubeadd - Kubernetes Context Manager

A small cross-platform CLI that imports contexts from kubeconfig files into your
own kubeconfig, and lists or deletes them again. Runs on **macOS, Linux and Windows**.

## Features

- Import contexts from any kubeconfig file (EKS, GKE, AKS, kubeadm, Rancher, ...)
- **Import AWS EKS clusters directly** (`--eks`): pick profile, region(s) and clusters from a list
- **Pick which contexts to import** when the file contains more than one (`1,3`, `1-2`, `all`)
- **Name the context, cluster and user separately** - or let cluster/user follow the context name
- Short default names for cloud contexts (`arn:aws:eks:...:cluster/prod` becomes `prod`)
- Conflict handling: overwrite, rename or skip when a name already exists; re-importing an unchanged file is a no-op
- Certificates referenced as files are embedded, so the imported context keeps working when the source file is gone
- Delete contexts together with the clusters/users nobody else uses (shared ones are kept)
- List contexts with their cluster, user, namespace and server
- Timestamped backup before every change, `--dry-run` to preview, `-y` for scripts and automation

## Prerequisites

- Python 3.8 or newer (no extra packages)
- `kubectl` in your `PATH` - it is used to read and write kubeconfig files, so `yq` is no longer needed
- AWS CLI v2, only for `--eks`

## Installation

### With pipx (all platforms)

```bash
pipx install git+https://github.com/ozkanpoyrazoglu/kubeadd.git
```

This puts a `kubeadd` command on your `PATH`.

### macOS / Linux from a clone

```bash
git clone https://github.com/ozkanpoyrazoglu/kubeadd.git
sudo ln -s "$PWD/kubeadd/kubeadd.py" /usr/local/bin/kubeadd
```

Or add an alias to `~/.zshrc` / `~/.bashrc`:

```bash
alias kubeadd="/path/to/kubeadd/kubeadd.py"
```

Existing aliases that point to `kubeadd.sh` keep working: it is now a thin wrapper around `kubeadd.py`.

### Windows from a clone

```powershell
git clone https://github.com/ozkanpoyrazoglu/kubeadd.git
```

Add the `kubeadd` folder to your `PATH`; `kubeadd.cmd` then lets you run `kubeadd` from both
cmd.exe and PowerShell (it uses the `py` launcher when available, otherwise `python`).

## Usage

```
kubeadd -f FILE [options]   import context(s) from FILE
kubeadd --eks [CLUSTER ...] import AWS EKS cluster(s)
kubeadd -l                  list contexts
kubeadd -d [CONTEXT ...]    delete context(s) (interactive when no name is given)
kubeadd -h                  show all options
```

The kubeconfig that is modified is the one kubectl uses: the first entry of `$KUBECONFIG`,
otherwise `~/.kube/config`. Use `--kubeconfig PATH` to pick another file.

### Import

```bash
kubeadd -f ~/Downloads/clusters.yaml
```

If the file holds several contexts you choose which ones to import:

```
📚 The file contains 3 contexts:
    1. arn:aws:eks:eu-west-1:123456789012:cluster/prod  (https://ABC.gr7.eu-west-1.eks.amazonaws.com)
    2. arn:aws:eks:eu-west-1:123456789012:cluster/stage  (https://DEF.gr7.eu-west-1.eks.amazonaws.com)
    3. arn:aws:eks:eu-west-1:123456789012:cluster/dev  (https://GHI.gr7.eu-west-1.eks.amazonaws.com)

Select context(s) to import (e.g. 1,3 / 1-2 / all): 1,2
```

For each selected context you can set the names; cluster and user names default to the
context name, which keeps generic names such as kubeadm's `kubernetes` from colliding:

```
📋 Found context:
   Context  : arn:aws:eks:eu-west-1:123456789012:cluster/prod
   Cluster  : arn:aws:eks:eu-west-1:123456789012:cluster/prod
   Server   : https://ABC.gr7.eu-west-1.eks.amazonaws.com
   User     : arn:aws:eks:eu-west-1:123456789012:cluster/prod

🏷️  Context name [prod]:
   Set cluster and user names separately? (y/N): y
   Cluster name [prod]: prod-eks
   User name [prod]: prod-admin
🌐 Server URL is https://ABC.gr7.eu-west-1.eks.amazonaws.com - is this correct? (Y/n):
```

When a context, cluster or user with the same name but different settings already exists you are asked to
**overwrite**, **rename** or **skip**. Finally you can switch to the new context; a backup is written first:

```
💾 Backup created: /Users/me/.kube/config.backup.20261028_143022
✅ Context 'prod' (cluster: prod-eks, user: prod-admin)
🎯 Current context: prod
```

#### Non-interactive import

Every question has a flag, and `-y` accepts the defaults for anything not given:

| Flag | Meaning |
| --- | --- |
| `-c, --context NAME` | context to import from the file (repeatable) |
| `--all` | import every context in the file |
| `-n, --name NAME` | new context name |
| `--cluster-name NAME` | new cluster name (default: context name) |
| `--user-name NAME` | new user name (default: context name) |
| `--namespace NS` | default namespace for the imported context(s) |
| `--server URL` | override the API server URL |
| `--overwrite` | replace existing entries with the same name instead of failing |
| `--switch` / `--no-switch` | make the (first) imported context current, or keep the current one |
| `--dry-run` | show what would happen without writing anything |

`--name`, `--cluster-name`, `--user-name` and `--server` apply only when a single context is imported.
With `-y`, a single imported context becomes the current context; with several, the current context
is kept unless `--switch` is given.

```bash
kubeadd -f admin.conf -n lab --cluster-name lab-cluster --user-name lab-admin -y
kubeadd -f eks.yaml --all -y --no-switch
kubeadd -f clusters.yaml -c dev -c staging -y --dry-run
```

### Import AWS EKS clusters

`--eks` runs `aws eks update-kubeconfig` for you and feeds the result through the same import flow,
so you get the same naming, conflict handling and backups. Requires the AWS CLI v2.

```bash
kubeadd --eks
```

Without arguments kubeadd asks for the AWS profile (when you have several and `AWS_PROFILE` is not set),
uses the profile's region and lets you pick from the clusters it finds:

```
👤 AWS profiles:
    1. default
    2. acme-prod

Select profile: 2
🌍 Region: eu-west-1 (change with --region or --all-regions)
🔍 Looking for EKS clusters in 1 region(s) ...
☸️  Found 3 EKS clusters:
    1. payments  (eu-west-1)
    2. platform  (eu-west-1)
    3. search  (eu-west-1)

Select cluster(s) to import (e.g. 1,3 / 1-2 / all): 1,2
```

| Flag | Meaning |
| --- | --- |
| `--eks CLUSTER ...` | import these clusters instead of choosing from a list |
| `--profile NAME` | AWS profile; it is stored in the kubeconfig so kubectl uses it to get tokens |
| `--region REGION` | region to look in (default: `AWS_REGION` / the profile's region) |
| `--all-regions` | look for clusters in every enabled region (in parallel) |
| `--role-arn ARN` | IAM role kubectl assumes when it requests a token |
| `--name-format FORMAT` | default context name, built from `{cluster}`, `{region}`, `{account}` and `{profile}` (default `{cluster}`) |

The import options above (`-n`, `--cluster-name`, `--user-name`, `--namespace`, `--all`, `--overwrite`,
`--switch`, `-y`, `--dry-run`) work with `--eks` too.

```bash
# same cluster name in several accounts: put the profile in the context name
kubeadd --eks prod --profile acme --region eu-west-1 --name-format '{profile}-{cluster}'

# every cluster of an account, all regions, no questions
kubeadd --eks --profile acme --all-regions --all --name-format '{cluster}-{region}' -y
```

If two clusters would get the same default name in one run, the second one falls back to its full ARN.
When an SSO session has expired kubeadd tells you to run `aws sso login --profile <profile>`.

### List

```
$ kubeadd -l
📁 Kubeconfig: /Users/me/.kube/config
   CONTEXT  CLUSTER   USER        NAMESPACE  SERVER
*  prod     prod-eks  prod-admin  -          https://ABC.gr7.eu-west-1.eks.amazonaws.com
   stage    stage     stage       apps       https://DEF.gr7.eu-west-1.eks.amazonaws.com
```

### Delete

```
$ kubeadd -d
🗑️  Contexts:
    1. prod  (https://ABC.gr7.eu-west-1.eks.amazonaws.com)  [current]
    2. stage  (https://DEF.gr7.eu-west-1.eks.amazonaws.com)

Select context(s) to delete (e.g. 1,3 / 1-2): 2

⚠️  The following entries will be removed:
   context  stage
   cluster  stage
   user     stage
Are you sure? (y/N): y
💾 Backup created: /Users/me/.kube/config.backup.20261028_143510
✅ Deleted 1 context(s)
```

Clusters and users that are still referenced by other contexts are kept. Without prompts:

```bash
kubeadd -d old-cluster other-cluster -y
```

## Backups

Before every change the current file is copied to `<kubeconfig>.backup.YYYYMMDD_HHMMSS`.
To roll back, copy a backup over the kubeconfig.

## Troubleshooting

**`kubectl is not installed or not in PATH`** - install kubectl
(`brew install kubectl`, `winget install Kubernetes.kubectl`, or see the
[Kubernetes docs](https://kubernetes.io/docs/tasks/tools/)).

**`python3: command not found` / `python` not found on Windows** - install Python 3.8+
(`winget install Python.Python.3.12` on Windows).

**Invalid server URL** - the API server URL must look like `https://server-address[:port][/path]`,
e.g. `https://k8s.example.com:6443` or `https://127.0.0.1:8443`.

**Emoji look garbled on Windows** - use Windows Terminal; the legacy console host has limited Unicode support.

## Development

```bash
python3 -m unittest discover -s tests -v
```

The end-to-end tests run real `kubectl` against temporary files and are skipped when kubectl is missing.
CI runs them on Linux, macOS and Windows.

## License

This project is open source and available under the MIT License.
