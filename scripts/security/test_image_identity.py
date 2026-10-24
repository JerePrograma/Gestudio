"""Small synthetic OCI proofs: no Docker, network, packages or image downloads."""
import base64
import copy
import gzip
import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path

import oci_image_proof as proof
import verify_image_identity as adapter


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def desc(raw, media):
    return {"digest": proof.digest(raw), "size": len(raw), "mediaType": media}


def synthetic_archive(path, corrupt_layer=False, unsafe=False):
    uncompressed = b"synthetic layer, not a production filesystem"
    compressed = gzip.compress(uncompressed, mtime=0)
    config = encoded({"architecture": "amd64", "os": "linux", "rootfs": {"type": "layers", "diff_ids": [proof.digest(uncompressed)]}})
    manifest = encoded({"schemaVersion": 2, "mediaType": proof.MANIFEST, "config": desc(config, proof.CONFIG), "layers": [desc(compressed, proof.GZIP)]})
    platform = desc(manifest, proof.MANIFEST) | {"platform": {"os": "linux", "architecture": "amd64"}}
    index = encoded({"schemaVersion": 2, "mediaType": proof.INDEX, "manifests": [platform]})
    root = encoded({"schemaVersion": 2, "manifests": [desc(index, proof.INDEX)]})
    blobs = {"index.json": root, "oci-layout": encoded({"imageLayoutVersion": "1.0.0"})}
    for raw in [config, manifest, index, compressed]:
        blobs["blobs/sha256/" + proof.digest(raw)[7:]] = raw
    if corrupt_layer:
        blobs["blobs/sha256/" + proof.digest(compressed)[7:]] = b"x" * len(compressed)
    if unsafe:
        blobs["../outside"] = b"rejected without extraction"
    with tarfile.open(path, "w") as archive:
        for name, raw in blobs.items():
            member = tarfile.TarInfo(name)
            member.size = len(raw)
            archive.addfile(member, io.BytesIO(raw))
    target = {"userInput": "/images/backend.tar", "imageID": proof.digest(config), "os": "linux", "architecture": "amd64",
              "config": base64.b64encode(config).decode(), "manifest": base64.b64encode(manifest).decode(),
              "manifestDigest": proof.digest(manifest), "layers": [{"digest": proof.digest(uncompressed)}]}
    return proof.digest(index), target


def synthetic_classic_archive(path, corrupt_layer=False):
    layer = b"synthetic classic uncompressed runtime layer"
    config = encoded({"architecture": "amd64", "os": "linux", "rootfs": {"type": "layers", "diff_ids": [proof.digest(layer)]}})
    config_path = proof.digest(config)[7:] + ".json"
    manifest = encoded([{"Config": config_path, "Layers": ["layer/layer.tar"], "RepoTags": None}])
    with tarfile.open(path, "w") as archive:
        for name, raw in [("manifest.json", manifest), (config_path, config), ("layer/layer.tar", b"altered" if corrupt_layer else layer)]:
            member = tarfile.TarInfo(name)
            member.size = len(raw)
            archive.addfile(member, io.BytesIO(raw))
    reported = encoded({"schemaVersion": 2, "mediaType": proof.DOCKER_MANIFEST,
                        "config": desc(config, proof.DOCKER_CONFIG), "layers": [desc(layer, proof.DOCKER_TAR)]})
    target = {"userInput": "/images/backend.tar", "imageID": proof.digest(config), "os": "linux", "architecture": "amd64",
              "config": base64.b64encode(config).decode(), "manifest": base64.b64encode(reported).decode(),
              "manifestDigest": proof.digest(reported), "layers": [{"digest": proof.digest(layer)}]}
    return proof.digest(config), target


def synthetic_dual_archive(path, delta=None, root_delta=None):
    """Moby28 classic store saves config-ID images with both manifest formats."""
    layer = b"synthetic Moby28 uncompressed layer"
    config = encoded({"architecture": "amd64", "os": "linux", "rootfs": {"type": "layers", "diff_ids": [proof.digest(layer)]}})
    blob_path = lambda raw: "blobs/sha256/" + proof.digest(raw)[7:]
    manifest_value = {"schemaVersion": 2, "mediaType": proof.MANIFEST, "config": desc(config, proof.CONFIG),
                      "layers": [desc(layer, proof.TAR)]}
    if delta:
        delta(manifest_value)
    oci_manifest = encoded(manifest_value)
    root_value = {"schemaVersion": 2, "mediaType": proof.INDEX, "manifests": [desc(oci_manifest, proof.MANIFEST)]}
    if root_delta:
        root_delta(root_value)
    root = encoded(root_value)
    classic = encoded([{"Config": blob_path(config), "Layers": [blob_path(layer)], "RepoTags": None}])
    blobs = {"manifest.json": classic, "index.json": root, "oci-layout": encoded({"imageLayoutVersion": "1.0.0"}),
             blob_path(config): config, blob_path(layer): layer, blob_path(oci_manifest): oci_manifest}
    with tarfile.open(path, "w") as archive:
        for name, raw in blobs.items():
            member = tarfile.TarInfo(name)
            member.size = len(raw)
            archive.addfile(member, io.BytesIO(raw))
    reported = encoded({"schemaVersion": 2, "mediaType": proof.DOCKER_MANIFEST,
                        "config": desc(config, proof.DOCKER_CONFIG), "layers": [desc(layer, proof.DOCKER_TAR)]})
    target = {"userInput": "/images/backend.tar", "imageID": proof.digest(config), "os": "linux", "architecture": "amd64",
              "config": base64.b64encode(config).decode(), "manifest": base64.b64encode(reported).decode(),
              "manifestDigest": proof.digest(reported), "layers": [{"digest": proof.digest(layer)}]}
    return proof.digest(config), target


class ImageIdentityTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="gestudio-oci-contract-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "image.tar"
        self.image_id, self.target = synthetic_archive(self.path)
        self.identity = proof.capture_identity(self.path, self.image_id)
        self.sbom = {"source": {"type": "image", "metadata": self.target}}

    def test_exact_selected_index_and_config_id_have_distinct_verified_roles(self):
        self.assertNotEqual(self.image_id, self.target["imageID"])
        self.assertEqual(adapter.validate_sbom(self.identity, self.sbom, self.image_id, "/images/backend.tar"), "oci-original")
        report = {"source": {"type": "image", "target": self.target}}
        self.assertEqual(adapter.validate_grype_sbom(self.identity, self.sbom, report, self.image_id, "/images/backend.tar"), "oci-original")

    def test_substituted_index_and_scanner_config_are_rejected(self):
        with self.assertRaises(ValueError):
            proof.capture_identity(self.path, self.target["imageID"])
        for field, value in [("imageID", self.image_id), ("config", base64.b64encode(b"{}").decode()), ("userInput", "/images/frontend.tar")]:
            bad = copy.deepcopy(self.sbom)
            bad["source"]["metadata"][field] = value
            with self.assertRaises(ValueError):
                adapter.validate_sbom(self.identity, bad, self.image_id, "/images/backend.tar")

    def test_compressed_layer_and_unsafe_tar_path_are_rejected(self):
        for options in [{"corrupt_layer": True}, {"unsafe": True}]:
            bad_path = self.path.with_name("bad.tar")
            image_id, _ = synthetic_archive(bad_path, **options)
            with self.assertRaises(ValueError):
                proof.capture_identity(bad_path, image_id)

    def test_report_layer_order_and_manifest_digest_are_not_accepted_by_size(self):
        for delta in [{"layers": [{"digest": "sha256:" + "0" * 64}]}, {"manifestDigest": "sha256:" + "0" * 64}]:
            bad = dict(self.target) | delta
            with self.assertRaises(ValueError):
                adapter.validate_grype_sbom(self.identity, self.sbom, {"source": {"type": "image", "target": bad}}, self.image_id, "/images/backend.tar")

    def test_classic_config_id_is_supported_with_verified_runtime_layers(self):
        classic = self.path.with_name("classic.tar")
        image_id, target = synthetic_classic_archive(classic)
        identity = proof.capture_identity(classic, image_id)
        self.assertEqual(identity["proofType"], "docker-config-content-chain")
        sbom = {"source": {"type": "image", "metadata": target}}
        self.assertEqual(adapter.validate_sbom(identity, sbom, image_id, "/images/backend.tar"), "docker-classic-config-and-verified-diff-ids")
        report = {"source": {"type": "image", "target": target}}
        self.assertEqual(adapter.validate_grype_sbom(identity, sbom, report, image_id, "/images/backend.tar"), "docker-classic-config-and-verified-diff-ids")

    def test_moby28_dual_format_binds_both_views_to_selected_config_and_layers(self):
        dual = self.path.with_name("dual.tar")
        image_id, target = synthetic_dual_archive(dual)
        identity = proof.capture_identity(dual, image_id)
        self.assertEqual(identity["archiveLayout"], "docker-save-oci-dual")
        sbom = {"source": {"type": "image", "metadata": target}}
        self.assertEqual(adapter.validate_sbom(identity, sbom, image_id, "/images/backend.tar"), "docker-classic-config-and-verified-diff-ids")
        self.assertEqual(adapter.validate_grype_sbom(identity, sbom, {"source": {"type": "image", "target": target}}, image_id, "/images/backend.tar"), "docker-classic-config-and-verified-diff-ids")

    def test_dual_format_conflicting_config_and_layer_descriptors_are_rejected(self):
        for field in ["config", "layers"]:
            with self.subTest(field=field):
                dual = self.path.with_name("dual-conflict.tar")
                def delta(value):
                    item = value["config"] if field == "config" else value["layers"][0]
                    item["digest"] = "sha256:" + "0" * 64
                image_id, _ = synthetic_dual_archive(dual, delta)
                with self.assertRaises(ValueError):
                    proof.capture_identity(dual, image_id)

    def test_dual_format_duplicate_or_wrong_size_index_descriptors_are_rejected(self):
        def duplicate(root):
            root["manifests"].append(copy.deepcopy(root["manifests"][0]))
        def wrong_size(root):
            root["manifests"][0]["size"] += 1
        for delta in [duplicate, wrong_size]:
            with self.subTest(delta=delta.__name__):
                dual = self.path.with_name("dual-index-conflict.tar")
                image_id, _ = synthetic_dual_archive(dual, root_delta=delta)
                with self.assertRaises(ValueError):
                    proof.capture_identity(dual, image_id)

    def test_real_oci_index_cannot_downgrade_to_added_classic_config_view(self):
        with tarfile.open(self.path, "r:") as archive:
            blobs = {item.name: archive.extractfile(item).read() for item in archive.getmembers()}
        config = base64.b64decode(self.target["config"])
        manifest = json.loads(base64.b64decode(self.target["manifest"]))
        blobs["manifest.json"] = encoded([{"Config": "blobs/sha256/" + proof.digest(config)[7:],
            "Layers": ["blobs/sha256/" + item["digest"][7:] for item in manifest["layers"]], "RepoTags": None}])
        with tarfile.open(self.path, "w") as archive:
            for name, raw in blobs.items():
                member = tarfile.TarInfo(name)
                member.size = len(raw)
                archive.addfile(member, io.BytesIO(raw))
        with self.assertRaises(ValueError):
            proof.capture_identity(self.path, self.target["imageID"])
        identity = proof.capture_identity(self.path, self.image_id)
        self.assertEqual(identity["proofType"], "docker-oci-content-chain")

    def test_captured_dual_proof_rejects_rehashed_manifest_substitution(self):
        dual = self.path.with_name("dual-proof.tar")
        image_id, _ = synthetic_dual_archive(dual)
        identity = proof.capture_identity(dual, image_id)
        manifest = json.loads(base64.b64decode(identity["ociManifest"]["rawBase64"]))
        manifest["config"]["digest"] = "sha256:" + "0" * 64
        raw = encoded(manifest)
        identity["ociManifest"] = proof.node(raw, proof.MANIFEST)
        root = json.loads(base64.b64decode(identity["archiveIndex"]["rawBase64"]))
        root["manifests"] = [desc(raw, proof.MANIFEST)]
        identity["archiveIndex"] = proof.node(encoded(root), proof.INDEX)
        with self.assertRaises(ValueError):
            proof.identity_model(identity, image_id)

    def test_classic_layer_and_selected_config_substitution_are_rejected(self):
        classic = self.path.with_name("classic.tar")
        image_id, _ = synthetic_classic_archive(classic, corrupt_layer=True)
        with self.assertRaises(ValueError):
            proof.capture_identity(classic, image_id)
        image_id, _ = synthetic_classic_archive(classic)
        with self.assertRaises(ValueError):
            proof.capture_identity(classic, "sha256:" + "0" * 64)

    def test_classic_scanner_manifest_cannot_replace_verified_diff_ids(self):
        classic = self.path.with_name("classic.tar")
        image_id, target = synthetic_classic_archive(classic)
        identity = proof.capture_identity(classic, image_id)
        bad = copy.deepcopy(target)
        manifest = json.loads(base64.b64decode(bad["manifest"]))
        manifest["layers"][0]["digest"] = "sha256:" + "0" * 64
        raw = encoded(manifest)
        bad["manifest"] = base64.b64encode(raw).decode()
        bad["manifestDigest"] = proof.digest(raw)
        with self.assertRaises(ValueError):
            adapter.validate_sbom(identity, {"source": {"type": "image", "metadata": bad}}, image_id, "/images/backend.tar")


if __name__ == "__main__":
    unittest.main()
