"""Publish an existing, fully tested CI draft; never rebuild or replace assets."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import zipfile
import xml.etree.ElementTree as ET


CERTIFICATE = "99f09bd9bce2572a966e3daea07718debb0ad4754f43b9742e03812c204f4796"
REQUIRED_JOBS = {"prepare", "checks", "build", "emulator (33)", "emulator (35)"}
REPORTS = {f"device-{kind}-test-results-api{api}.json"
           for api in (33, 35)
           for kind in ("alarm", "cleanup", "guardian", "notification", "popup", "speech", "entry")}


class ReleaseError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


class GitHub:
    def __init__(self, repo, token):
        require(re.fullmatch(r"[\w.-]+/[\w.-]+", repo), "Invalid repository")
        require(bool(token), "GH_TOKEN is required")
        self.repo, self.token = repo, token

    def __call__(self, path, method="GET", data=None, missing=False):
        request = urllib.request.Request(
            f"https://api.github.com/repos/{self.repo}{path}",
            method=method,
            data=None if data is None else json.dumps(data).encode(),
            headers={"Authorization": "Bearer " + self.token,
                     "Accept": "application/vnd.github+json",
                     "X-GitHub-Api-Version": "2022-11-28",
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            # Do not print request headers or tokens.
            raise ReleaseError(f"GitHub API {method} {path}: HTTP {error.code}") from None


def download_assets(repo, tag, directory):
    subprocess.run(["gh", "release", "download", tag, "--repo", repo,
                    "--dir", str(directory)], check=True)


def verify_signature(apk):
    sdk = Path(os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME", ""))
    signers = sorted(sdk.glob("build-tools/*/apksigner"),
                     key=lambda p: [int(x) for x in re.findall(r"\d+", p.parent.name)])
    require(bool(signers), "Android build-tools apksigner is unavailable")
    result = subprocess.run([str(signers[-1]), "verify", "--verbose", "--print-certs", str(apk)],
                            check=True, capture_output=True, text=True)
    match = re.search(r"certificate SHA-256 digest:\s*([0-9a-fA-F]+)", result.stdout)
    require(match is not None and match.group(1).lower() == CERTIFICATE,
            "APK signature does not match the fixed release certificate")


def inventory(release):
    result = {}
    for asset in release["assets"]:
        name = asset["name"]
        require(name not in result and re.fullmatch(r"[A-Za-z0-9_.-]+", name)
                and name not in (".", ".."), "Unsafe or duplicate release asset name")
        require(asset["state"] == "uploaded" and asset["size"] > 0,
                "Asset is incomplete: " + name)
        require(re.fullmatch(r"sha256:[0-9a-f]{64}", asset.get("digest") or ""),
                "Asset has no usable GitHub checksum: " + name)
        result[name] = (asset["id"], asset["size"], asset["digest"])
    return result


class Publisher:
    def __init__(self, api, repo, download=download_assets, signer=verify_signature):
        self.api, self.repo, self.download, self.signer = api, repo, download, signer

    def source_text(self, path, sha):
        file = self.api("/contents/" + path + "?ref=" + sha)
        require(file.get("encoding") == "base64", "Unexpected source file encoding")
        return base64.b64decode(file["content"], validate=False).decode("utf-8")

    def tag_commit(self, tag):
        ref = self.api("/git/ref/tags/" + tag, missing=True)
        if ref is None:
            return None
        obj = ref["object"]
        for _ in range(8):
            if obj["type"] == "commit":
                return obj["sha"]
            require(obj["type"] == "tag", "Unexpected release tag object")
            obj = self.api("/git/tags/" + obj["sha"])["object"]
        raise ReleaseError("Release tag nesting is too deep")

    def find_draft(self, tag):
        for page in range(1, 101):
            releases = self.api(f"/releases?per_page=100&page={page}")
            matches = [r for r in releases if r["tag_name"] == tag]
            require(len(matches) <= 1, "Multiple CI drafts use the same tag")
            if matches:
                return matches[0]
            if len(releases) < 100:
                break
        raise ReleaseError("CI draft is missing; select the original successful build run")

    def validate_files(self, directory, assets, sha, version, build):
        apk = f"timed-memo-{version}-arm64.apk"
        required = REPORTS | {apk, "BUILD_INFO.json", "SHA256SUMS.txt", "native-test-results.zip"}
        require(required <= assets.keys(), "Required APK or test report assets are missing")
        require({p.name for p in directory.iterdir()} == assets.keys(),
                "Downloaded assets differ from the draft")
        for name, (_, size, digest) in assets.items():
            path = directory / name
            require(path.is_file() and path.stat().st_size == size, "Asset size mismatch: " + name)
            with path.open("rb") as stream:
                actual = "sha256:" + hashlib.file_digest(stream, "sha256").hexdigest()
            require(actual == digest, "Asset SHA-256 mismatch: " + name)
        info = json.loads((directory / "BUILD_INFO.json").read_text())
        require(info.get("version") == version and info.get("build") == build
                and info.get("source_commit") == sha
                and info.get("package") == "com.niceday.memo.stable"
                and info.get("abi") == "arm64-v8a", "Build metadata does not match the tested source")
        require(info.get("signing") == "release" and info.get("certificate_sha256") == CERTIFICATE,
                "Build does not use the fixed release signing certificate")
        require(info.get("reboot_tests_run") is False, "Unexpected reboot-test metadata")
        require((directory / "SHA256SUMS.txt").read_text().split()
                == [assets[apk][2].removeprefix("sha256:"), apk], "APK checksum manifest mismatch")
        for report in REPORTS:
            require(isinstance(json.loads((directory / report).read_text()), dict),
                    "Invalid device test report: " + report)
        count = 0
        with zipfile.ZipFile(directory / "native-test-results.zip") as archive:
            for name in archive.namelist():
                if name.endswith(".xml"):
                    root = ET.fromstring(archive.read(name))
                    suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
                    for suite in suites:
                        require(int(suite.get("failures", 0)) == 0
                                and int(suite.get("errors", 0)) == 0, "Native tests did not pass")
                        count += int(suite.get("tests", 0)) - int(suite.get("skipped", 0))
        require(count > 0, "Native test results are empty")
        self.signer(directory / apk)

    def publish(self, run_id, current_run_id=None):
        require(re.fullmatch(r"[1-9][0-9]*", str(run_id)), "A positive source run ID is required")
        run_id = int(run_id)
        run = self.api(f"/actions/runs/{run_id}")
        sha = run["head_sha"]
        require(re.fullmatch(r"[0-9a-f]{40}", sha), "Invalid source commit")
        require(run.get("repository", {}).get("full_name") == self.repo
                and run.get("head_branch") == "main"
                and run.get("path") == ".github/workflows/android.yml"
                and run.get("event") in ("push", "workflow_dispatch"),
                "Source run is not this repository's trusted main build")
        require(run["status"] == "completed" or
                (str(run_id) == str(current_run_id) and run["status"] == "in_progress"),
                "Source run is still running")
        data = self.api(f"/actions/runs/{run_id}/jobs?filter=latest&per_page=100")
        require(data["total_count"] <= 100, "Too many source jobs; review the publication gate")
        jobs = data["jobs"]
        require({j["name"] for j in jobs} <= REQUIRED_JOBS | {"publish"},
                "A new verification job needs to be added to the publication gate")
        for name in REQUIRED_JOBS:
            matches = [j for j in jobs if j["name"] == name]
            require(len(matches) == 1 and matches[0]["status"] == "completed"
                    and matches[0]["conclusion"] == "success",
                    "Required verification did not pass: " + name)
        tag = self.source_text(".release-version", sha).strip()
        require(re.fullmatch(r"v\d+\.\d+\.\d+", tag), "Invalid release version")
        version = tag[1:]
        match = re.search(r"^version:\s*([^+\s]+)\+(\d+)", self.source_text("pubspec.yaml", sha), re.M)
        require(match is not None and match[1] == version, "Source version files disagree")
        build = int(match[2])
        require(self.source_text("docs/signing-certificate.sha256", sha).strip().lower() == CERTIFICATE,
                "Fixed certificate in source changed")
        notes = self.source_text(f"docs/releases/{tag}.md", sha)
        existing = self.api("/releases/tags/" + tag, missing=True)
        if existing is not None:
            require(not existing["draft"], "The target version already has another draft")
            required = REPORTS | {f"timed-memo-{version}-arm64.apk", "BUILD_INFO.json",
                                  "SHA256SUMS.txt", "native-test-results.zip"}
            require(required <= inventory(existing).keys(), "Existing Release is incomplete")
            target = self.tag_commit(tag)
            require(bool(target), "Published release has no tag")
            # Never overwrite a released version after another commit or CI-only update.
            return {"status": "already_published" if target == sha else "skipped_existing_version",
                    "version": tag, "url": existing["html_url"], "source_commit": target}
        draft = self.find_draft(f"ci-{run_id}")
        require(draft["draft"] and draft["target_commitish"] == sha,
                "CI draft does not match the tested source commit")
        assets = inventory(draft)
        with tempfile.TemporaryDirectory(prefix="memo-release-") as temp:
            directory = Path(temp)
            self.download(self.repo, draft["tag_name"], directory)
            self.validate_files(directory, assets, sha, version, build)
        latest = self.api(f"/releases/{draft['id']}")
        require(latest["draft"] and latest["tag_name"] == draft["tag_name"]
                and latest["target_commitish"] == sha and inventory(latest) == assets,
                "CI draft changed during validation; publication stopped")
        target = self.tag_commit(tag)
        require(target is None or target == sha, "Release tag already points to another commit")
        if target is None:
            self.api("/git/refs", "POST", {"ref": "refs/tags/" + tag, "sha": sha})
            # The ref read is served from a cache that lags the write by a second
            # or two. Reading back exactly once failed the v0.9.9 release even
            # though the tag had been created correctly, so retry with backoff
            # instead of declaring failure on the first empty response.
            target = self.tag_commit(tag)
            for _ in range(7):
                if target == sha:
                    break
                time.sleep(2)
                target = self.tag_commit(tag)
        require(target == sha, "Release tag verification failed")
        self.api(f"/releases/{draft['id']}", "PATCH", {
            "tag_name": tag, "target_commitish": sha,
            "name": f"超级提醒 {tag} · 固定签名新版", "body": notes,
            "draft": False, "prerelease": True, "make_latest": "false"})
        published = self.api("/releases/tags/" + tag)
        require(published["id"] == draft["id"] and not published["draft"]
                and published["prerelease"] and published["tag_name"] == tag
                and published["body"] == notes and inventory(published) == assets
                and self.tag_commit(tag) == sha, "Published release verification failed")
        return {"status": "published", "version": tag, "url": published["html_url"],
                "source_commit": sha, "assets": len(assets)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_id")
    args = parser.parse_args()
    repo = os.environ.get("GH_REPO") or os.environ.get("GITHUB_REPOSITORY", "")
    result = Publisher(GitHub(repo, os.environ.get("GH_TOKEN", "")), repo).publish(
        args.run_id, os.environ.get("GITHUB_RUN_ID"))
    print(json.dumps(result, ensure_ascii=False))
    if path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(path, "a") as summary:
            summary.write("## Release result\n\n" + json.dumps(result, ensure_ascii=False) + "\n")
            if result["status"] == "skipped_existing_version":
                summary.write("\nVersion already released from another commit. Bump the version to publish changes.\n")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None
