import base64
import copy
import hashlib
import io
import json
import unittest
import zipfile

from publish_release import CERTIFICATE, Publisher, ReleaseError, REQUIRED_JOBS, REPORTS


SHA = "c" * 40
REPO = "niceday-hh/codex_flutter2"


class Fixture:
    def __init__(self, version="0.9.1", build=12):
        self.version, self.release_tag = version, "v" + version
        self.writes = []
        self.signature_checks = 0
        self.tag = None
        self.existing = None
        self.before_refresh = lambda: None
        self.run = {"head_sha": SHA, "status": "completed", "head_branch": "main",
                    "repository": {"full_name": REPO}, "event": "push",
                    "path": ".github/workflows/android.yml"}
        self.jobs = [{"name": name, "status": "completed", "conclusion": "success"}
                     for name in sorted(REQUIRED_JOBS)]
        self.jobs.append({"name": "publish", "status": "completed", "conclusion": "failure"})
        self.sources = {".release-version": self.release_tag + "\n",
                        "pubspec.yaml": f"version: {version}+{build}\n",
                        "docs/signing-certificate.sha256": CERTIFICATE + "\n",
                        f"docs/releases/{self.release_tag}.md": f"# 超级提醒 {self.release_tag}\n\n版本说明\n"}
        apk = f"timed-memo-{version}-arm64.apk"
        payload = {apk: b"test APK bytes", **{p: b'{"passed":true}' for p in REPORTS}}
        payload["SHA256SUMS.txt"] = (hashlib.sha256(payload[apk]).hexdigest() + "  " + apk + "\n").encode()
        payload["BUILD_INFO.json"] = json.dumps({
            "version": version, "build": build, "source_commit": SHA,
            "package": "com.niceday.memo.stable", "abi": "arm64-v8a",
            "signing": "release", "certificate_sha256": CERTIFICATE,
            "reboot_tests_run": False}).encode()
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("TEST-native.xml", '<testsuite tests="58" failures="0" errors="0"/>')
        payload["native-test-results.zip"] = archive.getvalue()
        self.payload = payload
        self.draft = {"id": 99, "tag_name": "ci-123", "target_commitish": SHA, "draft": True,
                      "assets": [{"id": i, "name": name, "size": len(body), "state": "uploaded",
                                  "digest": "sha256:" + hashlib.sha256(body).hexdigest()}
                                 for i, (name, body) in enumerate(payload.items(), 1)]}

    def api(self, path, method="GET", data=None, missing=False):
        if method != "GET":
            self.writes.append((path, method, data))
            if path == "/git/refs":
                self.tag = data["sha"]
            elif path == "/releases/99":
                self.existing = {**copy.deepcopy(self.draft), **data,
                                 "html_url": "https://github.com/" + REPO + "/releases/tag/" + self.release_tag}
            else:
                raise AssertionError(path)
            return {}
        if path == "/actions/runs/123":
            return self.run
        if path == "/actions/runs/123/jobs?filter=latest&per_page=100":
            return {"total_count": len(self.jobs), "jobs": self.jobs}
        if path.startswith("/contents/"):
            name, ref = path.removeprefix("/contents/").split("?ref=")
            assert ref == SHA
            return {"encoding": "base64", "content": base64.b64encode(self.sources[name].encode()).decode()}
        if path == "/releases/tags/" + self.release_tag:
            return self.existing
        if path == "/releases?per_page=100&page=1":
            return [copy.deepcopy(self.draft)]
        if path == "/releases/99":
            self.before_refresh()
            return self.draft
        if path == "/git/ref/tags/" + self.release_tag:
            return None if self.tag is None else {"object": {"type": "commit", "sha": self.tag}}
        raise AssertionError(path)

    def download(self, repo, tag, directory):
        assert repo == REPO and tag == "ci-123"
        for name, body in self.payload.items():
            (directory / name).write_bytes(body)

    def signer(self, path):
        assert path.name == f"timed-memo-{self.version}-arm64.apk" and path.is_file()
        self.signature_checks += 1

    def publisher(self):
        return Publisher(self.api, REPO, self.download, self.signer)

    def replace_payload(self, name, content):
        self.payload[name] = content
        asset = next(x for x in self.draft["assets"] if x["name"] == name)
        asset.update(size=len(content), digest="sha256:" + hashlib.sha256(content).hexdigest())


class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.f = Fixture()

    def rejected(self, fragment):
        with self.assertRaisesRegex(ReleaseError, fragment):
            self.f.publisher().publish(123)
        self.assertEqual(self.f.writes, [], "Invalid build must not change tags or Releases")

    def test_completed_build_promotes_same_draft_and_preserves_all_assets(self):
        before = copy.deepcopy(self.f.draft["assets"])
        result = self.f.publisher().publish(123)
        self.assertEqual(result["status"], "published")
        self.assertEqual(result["assets"], 16)
        self.assertEqual(self.f.existing["id"], 99)
        self.assertEqual(self.f.existing["assets"], before)
        self.assertEqual(self.f.signature_checks, 1)
        self.assertEqual([m for _, m, _ in self.f.writes], ["POST", "PATCH"])
        self.assertEqual(self.f.tag, SHA)

    def test_failed_flutter_checks_are_rejected(self):
        next(j for j in self.f.jobs if j["name"] == "checks")["conclusion"] = "failure"
        self.rejected("checks")

    def test_future_version_is_derived_from_the_tested_source(self):
        self.f = Fixture(version="1.2.3", build=99)
        result = self.f.publisher().publish(123)
        self.assertEqual(result["version"], "v1.2.3")
        self.assertEqual(self.f.existing["tag_name"], "v1.2.3")
        self.assertEqual(self.f.existing["body"], self.f.sources["docs/releases/v1.2.3.md"])

    def test_missing_second_android_version_is_rejected(self):
        self.f.jobs = [j for j in self.f.jobs if j["name"] != "emulator (35)"]
        self.rejected("emulator")

    def test_new_verification_job_requires_gate_update(self):
        self.f.jobs.append({"name": "new security gate", "status": "completed", "conclusion": "failure"})
        self.rejected("new verification job")

    def test_fork_or_non_main_source_is_rejected(self):
        self.f.run["head_branch"] = "untrusted"
        self.rejected("trusted main build")

    def test_other_repository_is_rejected(self):
        self.f.run["repository"]["full_name"] = "someone/else"
        self.rejected("trusted main build")

    def test_other_in_progress_run_is_rejected(self):
        self.f.run["status"] = "in_progress"
        self.rejected("still running")

    def test_normal_publish_job_may_finish_its_own_in_progress_workflow(self):
        self.f.run["status"] = "in_progress"
        self.assertEqual(self.f.publisher().publish(123, current_run_id="123")["status"], "published")

    def test_version_files_must_agree(self):
        self.f.sources["pubspec.yaml"] = "version: 0.9.2+13\n"
        self.rejected("version files disagree")

    def test_unsigned_build_is_rejected(self):
        info = json.loads(self.f.payload["BUILD_INFO.json"])
        info["signing"] = "unsigned"
        self.f.replace_payload("BUILD_INFO.json", json.dumps(info).encode())
        self.rejected("fixed release signing")

    def test_downloaded_apk_tampering_is_rejected(self):
        self.f.payload["timed-memo-0.9.1-arm64.apk"] = b"fake APK bytes"
        self.rejected("SHA-256 mismatch")

    def test_wrong_build_source_is_rejected(self):
        info = json.loads(self.f.payload["BUILD_INFO.json"])
        info["source_commit"] = "d" * 40
        self.f.replace_payload("BUILD_INFO.json", json.dumps(info).encode())
        self.rejected("metadata")

    def test_missing_report_is_rejected(self):
        self.f.draft["assets"] = [a for a in self.f.draft["assets"] if a["name"] not in REPORTS]
        self.rejected("test report assets are missing")

    def test_native_test_failures_are_rejected(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("TEST.xml", '<testsuite tests="58" failures="1" errors="0"/>')
        self.f.replace_payload("native-test-results.zip", archive.getvalue())
        self.rejected("Native tests did not pass")

    def test_certificate_failure_never_creates_release(self):
        def reject(_):
            raise ReleaseError("certificate mismatch")
        self.f.signer = reject
        self.rejected("certificate mismatch")

    def test_assets_changed_during_validation_are_rejected(self):
        self.f.before_refresh = lambda: self.f.draft["assets"][0].update(id=500)
        self.rejected("changed during validation")

    def test_conflicting_existing_tag_is_not_moved(self):
        self.f.tag = "d" * 40
        self.rejected("another commit")

    def test_repeating_publication_does_not_modify_release(self):
        publisher = self.f.publisher()
        publisher.publish(123)
        writes = copy.deepcopy(self.f.writes)
        self.assertEqual(publisher.publish(123)["status"], "already_published")
        self.assertEqual(self.f.writes, writes)

    def test_released_version_from_another_commit_is_never_overwritten(self):
        self.f.publisher().publish(123)
        self.f.tag = "d" * 40
        writes = copy.deepcopy(self.f.writes)
        result = self.f.publisher().publish(123)
        self.assertEqual(result["status"], "skipped_existing_version")
        self.assertEqual(self.f.writes, writes)

    def test_incomplete_existing_release_is_not_reported_as_success(self):
        self.f.publisher().publish(123)
        self.f.existing["assets"] = self.f.existing["assets"][:-1]
        writes = copy.deepcopy(self.f.writes)
        with self.assertRaisesRegex(ReleaseError, "Existing Release is incomplete"):
            self.f.publisher().publish(123)
        self.assertEqual(self.f.writes, writes)

    def test_all_skipped_native_tests_are_rejected(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("TEST.xml", '<testsuite tests="58" failures="0" errors="0" skipped="58"/>')
        self.f.replace_payload("native-test-results.zip", archive.getvalue())
        self.rejected("Native test results are empty")

    def test_invalid_run_id_is_rejected_before_network_access(self):
        with self.assertRaisesRegex(ReleaseError, "positive source run ID"):
            self.f.publisher().publish("123\nnot a run")
        self.assertEqual(self.f.writes, [])


if __name__ == "__main__":
    unittest.main()
