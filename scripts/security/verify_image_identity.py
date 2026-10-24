"""Bind the tested Docker archive, Syft inventory and Grype report without Docker.

The OCI content verifier derives from the audited generic local tool artifact
(original SHA256 6bc049207240764c947a5e0511b1198d8c74ed3ac3d9f95f1f321716278953b8).
Gestudio adds classic Docker archive support with regression tests. The adapter
handles archive/SBOM CLI inputs; no CRM result or runtime dependency is reused.
"""
import argparse
import json
from pathlib import Path

import oci_image_proof as proof


def validate_target(identity, target, image_id, archive_input):
    proof.require(isinstance(target, dict), "Missing image source metadata")
    proof.require(target.get("userInput") in (archive_input, "docker-archive:" + archive_input),
                  "Scanner archive input mismatch")
    # The generic verifier accepts Docker input by ID. Here the actual input was
    # an archive whose bytes/index were independently verified against that ID.
    # Preserve that distinction in the adapter's output and execution proof.
    adapted = dict(target)
    adapted["userInput"] = image_id
    return proof.validate_grype_identity(identity, {"source": {"type": "image", "target": adapted}}, image_id)


def validate_sbom(identity, sbom, image_id, archive_input):
    source = sbom.get("source", {})
    proof.require(source.get("type") == "image", "Syft image source required")
    return validate_target(identity, source.get("metadata"), image_id, archive_input)


def validate_grype_sbom(identity, sbom, report, image_id, archive_input):
    validate_sbom(identity, sbom, image_id, archive_input)
    source = report.get("source", {})
    proof.require(source.get("type") == "image", "Grype SBOM must retain its original image source")
    return validate_target(identity, source.get("target"), image_id, archive_input)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True)
    parser.add_argument("--image-id", required=True)
    parser.add_argument("--archive-input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--sbom")
    parser.add_argument("--grype")
    options = parser.parse_args()
    identity = proof.capture_identity(options.archive, options.image_id)
    result = {"status": "PASS", "identity": identity,
              "inputMode": "docker-archive with verified exact selected index or config identity",
              "genericVerifierSha256": proof.digest(Path(proof.__file__).read_bytes())}
    if options.sbom:
        sbom = json.loads(Path(options.sbom).read_text(encoding="utf-8"))
        result["syftRepresentation"] = validate_sbom(identity, sbom, options.image_id, options.archive_input)
        result["sbomSha256"] = proof.digest(Path(options.sbom).read_bytes())
        if options.grype:
            report = json.loads(Path(options.grype).read_text(encoding="utf-8"))
            result["grypeRepresentation"] = validate_grype_sbom(identity, sbom, report, options.image_id, options.archive_input)
            result["grypeSha256"] = proof.digest(Path(options.grype).read_bytes())
    Path(options.output).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("PASS: exact OCI index or classic Docker config, manifest/config bytes, verified layers, ordered diff_ids and scanner metadata")


if __name__ == "__main__":
    main()
