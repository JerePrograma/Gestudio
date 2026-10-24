"""Content proof for OCI-index and classic config-ID Docker image archives.

Capture reads an archive without extracting files and verifies every runtime layer.
Validation consumes that controlled capture; its file hash belongs in the release
manifest. Report layer sizes are deliberately not used: Grype's source layer
sizes describe a different representation and may be zero.

Gestudio extends the audited generic OCI helper with classic Docker archives;
the original SHA256/provenance is recorded by the adjacent adapter.
"""
import base64
import gzip
import hashlib
import json
import re
import tarfile
from pathlib import Path

INDEX = 'application/vnd.oci.image.index.v1+json'
MANIFEST = 'application/vnd.oci.image.manifest.v1+json'
CONFIG = 'application/vnd.oci.image.config.v1+json'
GZIP = 'application/vnd.oci.image.layer.v1.tar+gzip'
TAR = 'application/vnd.oci.image.layer.v1.tar'
DOCKER_MANIFEST = 'application/vnd.docker.distribution.manifest.v2+json'
DOCKER_CONFIG = 'application/vnd.docker.container.image.v1+json'
DOCKER_GZIP = 'application/vnd.docker.image.rootfs.diff.tar.gzip'
DOCKER_TAR = 'application/vnd.docker.image.rootfs.diff.tar'


def require(condition, code):
    if not condition:
        raise ValueError(code)


def digest(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def sha256(value):
    require(isinstance(value, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', value), 'Invalid SHA256')
    return value


def integer(value):
    require(type(value) is int and value >= 0, 'Invalid size')
    return value


def strict_json(raw):
    require(isinstance(raw, bytes) and len(raw) <= 1024 * 1024, 'Invalid JSON size')

    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result

    def constant(_):
        raise ValueError('Invalid JSON constant')

    return json.loads(raw.decode('utf-8'), object_pairs_hook=pairs, parse_constant=constant)


def raw64(value):
    require(isinstance(value, str), 'Missing base64 bytes')
    raw = base64.b64decode(value, validate=True)
    require(base64.b64encode(raw).decode('ascii') == value, 'Noncanonical base64')
    return raw


def descriptor(value, media=None):
    require(isinstance(value, dict), 'Missing descriptor')
    sha256(value.get('digest'))
    integer(value.get('size'))
    if media:
        require(value.get('mediaType') == media, 'Unexpected descriptor media type')
    return value


def node(raw, media):
    return dict(digest=digest(raw), size=len(raw), mediaType=media,
                rawBase64=base64.b64encode(raw).decode('ascii'))


def decode_node(value, expected):
    descriptor(value, expected)
    raw = raw64(value.get('rawBase64'))
    require(len(raw) == value['size'] and digest(raw) == value['digest'], 'Node bytes mismatch')
    parsed = strict_json(raw)
    require(isinstance(parsed, dict), 'JSON object required')
    if expected in (INDEX, MANIFEST):
        require(type(parsed.get('schemaVersion')) is int and parsed['schemaVersion'] == 2,
                'Schema version 2 required')
        require(parsed.get('mediaType') == expected, 'Unexpected JSON media type')
    return raw, parsed


def platform_descriptor(index):
    require(isinstance(index.get('manifests'), list), 'Missing platform manifests')
    matches = [entry for entry in index['manifests'] if isinstance(entry, dict)
               and entry.get('platform', {}).get('os') == 'linux'
               and entry.get('platform', {}).get('architecture') == 'amd64']
    require(len(matches) == 1, 'Exactly one linux/amd64 manifest required')
    require(matches[0]['platform'].get('variant', '') == '', 'Unexpected platform variant')
    return descriptor(matches[0], MANIFEST)


def hash_stream(stream):
    result = hashlib.sha256()
    size = 0
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(chunk)
        size += len(chunk)
    return 'sha256:' + result.hexdigest(), size


def identity_model(identity, image_id):
    sha256(image_id)
    if identity.get('proofType') == 'docker-config-content-chain':
        return classic_identity_model(identity, image_id)
    require(type(identity.get('schemaVersion')) is int and identity['schemaVersion'] == 1
            and identity.get('proofType') == 'docker-oci-content-chain',
            'Unsupported identity proof')
    require(identity.get('selectedImageId') == image_id and identity.get('platform') == 'linux/amd64',
            'Selected image/platform mismatch')
    sha256(identity['archive']['sha256'])
    integer(identity['archive']['bytes'])
    _, index = decode_node(identity['index'], INDEX)
    require(identity['index']['digest'] == image_id, 'Index is not selected image ID')
    selected = platform_descriptor(index)
    manifest_raw, manifest = decode_node(identity['platformManifest'], MANIFEST)
    require(selected['digest'] == digest(manifest_raw) and selected['size'] == len(manifest_raw),
            'Platform descriptor mismatch')
    config_descriptor = descriptor(manifest.get('config'), CONFIG)
    config_raw, config = decode_node(identity['config'], CONFIG)
    require(config_descriptor['digest'] == digest(config_raw) and config_descriptor['size'] == len(config_raw),
            'Config descriptor mismatch')
    require(config.get('os') == 'linux' and config.get('architecture') == 'amd64'
            and config.get('variant', '') == '', 'Config platform mismatch')
    rootfs = config.get('rootfs', {})
    require(rootfs.get('type') == 'layers' and isinstance(rootfs.get('diff_ids'), list), 'Invalid rootfs')
    require(isinstance(manifest.get('layers'), list) and isinstance(identity.get('layers'), list), 'Missing layers')
    require(len(manifest['layers']) == len(rootfs['diff_ids']) == len(identity['layers']), 'Layer count mismatch')
    for layer, diff_id, proof in zip(manifest['layers'], rootfs['diff_ids'], identity['layers']):
        descriptor(layer)
        require(layer.get('mediaType') in (GZIP, TAR), 'Unsupported layer compression')
        sha256(diff_id)
        require(proof.get('compressedDigest') == layer['digest']
                and proof.get('compressedSize') == layer['size']
                and proof.get('mediaType') == layer['mediaType']
                and proof.get('diffId') == diff_id, 'Layer proof mismatch')
        integer(proof.get('uncompressedSize'))
    return manifest_raw, manifest, config_raw, rootfs['diff_ids']


def capture_oci_identity(archive, image_id, platform='linux/amd64'):
    """Verify exact-index archive and compressed→uncompressed hashes; no Docker calls."""
    archive = Path(archive)
    sha256(image_id)
    require(platform == 'linux/amd64', 'Only linux/amd64 is approved')
    with archive.open('rb') as stream:
        archive_digest, archive_size = hash_stream(stream)
    with tarfile.open(archive, 'r:') as source:
        members = {}
        for entry in source.getmembers():
            name = entry.name
            require(name not in members, 'Duplicate tar member')
            require(name and '\\' not in name and ':' not in name
                    and all(part not in ('', '.', '..') for part in name.rstrip('/').split('/')),
                    'Unsafe tar path')
            require(entry.isfile() or entry.isdir(), 'Tar links and special members are refused')
            members[name] = entry

        def read(name):
            require(name in members and members[name].isfile(), 'Missing regular archive entry')
            require(members[name].size <= 1024 * 1024, 'Oversized JSON entry')
            with source.extractfile(members[name]) as stream:
                return stream.read()

        def read_blob(item):
            descriptor(item)
            raw = read('blobs/sha256/' + item['digest'][7:])
            require(digest(raw) == item['digest'] and len(raw) == item['size'], 'Blob hash/size mismatch')
            return raw

        root = strict_json(read('index.json'))
        require(type(root.get('schemaVersion')) is int and root['schemaVersion'] == 2
                and isinstance(root.get('manifests'), list), 'Invalid archive index')
        selected = [entry for entry in root['manifests'] if entry.get('digest') == image_id]
        require(len(selected) == 1, 'Archive must reference the exact selected image ID once')
        descriptor(selected[0], INDEX)
        index_raw = read_blob(selected[0])
        index = strict_json(index_raw)
        require(index.get('schemaVersion') == 2 and index.get('mediaType') == INDEX, 'Invalid selected index')
        selected_platform = platform_descriptor(index)
        manifest_raw = read_blob(selected_platform)
        manifest = strict_json(manifest_raw)
        require(manifest.get('schemaVersion') == 2 and manifest.get('mediaType') == MANIFEST, 'Invalid platform manifest')
        descriptor(manifest.get('config'), CONFIG)
        config_raw = read_blob(manifest['config'])
        config = strict_json(config_raw)
        require(config.get('os') == 'linux' and config.get('architecture') == 'amd64', 'Config platform mismatch')
        diff_ids = config.get('rootfs', {}).get('diff_ids', [])
        require(isinstance(manifest.get('layers'), list) and len(manifest['layers']) == len(diff_ids), 'Layer count mismatch')
        layers = []
        for item, diff_id in zip(manifest['layers'], diff_ids):
            descriptor(item)
            require(item.get('mediaType') in (GZIP, TAR), 'Unsupported layer compression')
            name = 'blobs/sha256/' + item['digest'][7:]
            require(name in members and members[name].isfile(), 'Missing regular layer blob')
            require(members[name].size == item['size'], 'Layer tar size mismatch')
            with source.extractfile(members[name]) as stream:
                actual_digest, actual_size = hash_stream(stream)
            require(actual_digest == item['digest'] and actual_size == item['size'], 'Compressed layer mismatch')
            with source.extractfile(members[name]) as stream:
                if item['mediaType'] == GZIP:
                    with gzip.GzipFile(fileobj=stream) as expanded:
                        actual_diff_id, expanded_size = hash_stream(expanded)
                else:
                    actual_diff_id, expanded_size = hash_stream(stream)
            require(actual_diff_id == sha256(diff_id), 'Expanded layer diff_id mismatch')
            layers.append(dict(mediaType=item['mediaType'], compressedDigest=actual_digest,
                               compressedSize=actual_size, diffId=actual_diff_id, uncompressedSize=expanded_size))
    result = dict(schemaVersion=1, proofType='docker-oci-content-chain', selectedImageId=image_id,
                  platform=platform, archive=dict(sha256=archive_digest, bytes=archive_size),
                  index=node(index_raw, INDEX), platformManifest=node(manifest_raw, MANIFEST),
                  config=node(config_raw, CONFIG), layers=layers)
    identity_model(result, image_id)
    return result


def validate_grype_identity(identity, report, image_id):
    """Validate a controlled-capture proof plus pinned Grype image report; return representation."""
    manifest_raw, manifest, config_raw, diff_ids = identity_model(identity, image_id)
    source = report.get('source', {})
    target = source.get('target', {})
    require(source.get('type') == 'image' and isinstance(target, dict), 'Image source required')
    require(target.get('userInput') == image_id, 'Scanner must receive exact selected image ID')
    require(target.get('os') == 'linux' and target.get('architecture') == 'amd64', 'Scanner platform mismatch')
    require(target.get('imageID') == digest(config_raw), 'Scanner config ID mismatch')
    scanner_config = raw64(target.get('config'))
    strict_json(scanner_config)
    require(scanner_config == config_raw, 'Scanner config bytes mismatch')
    scanner_manifest_raw = raw64(target.get('manifest'))
    require(digest(scanner_manifest_raw) == sha256(target.get('manifestDigest')), 'Scanner manifest hash mismatch')
    scanner_manifest = strict_json(scanner_manifest_raw)
    require(isinstance(target.get('layers'), list) and all(isinstance(entry, dict) for entry in target['layers'])
            and [entry.get('digest') for entry in target['layers']] == diff_ids, 'Scanner ordered diff_ids mismatch')
    if identity.get('proofType') == 'docker-config-content-chain':
        require(scanner_manifest.get('schemaVersion') == 2 and scanner_manifest.get('mediaType') == DOCKER_MANIFEST,
                'Classic scanner Docker-v2 manifest required')
        config = descriptor(scanner_manifest.get('config'), DOCKER_CONFIG)
        require(config['digest'] == image_id and config['size'] == len(config_raw), 'Classic scanner config descriptor mismatch')
        reported_layers = scanner_manifest.get('layers')
        require(isinstance(reported_layers, list) and len(reported_layers) == len(diff_ids), 'Classic scanner manifest layers mismatch')
        digests = []
        for entry in reported_layers:
            descriptor(entry)
            require(entry.get('mediaType') in (DOCKER_GZIP, DOCKER_TAR), 'Classic scanner layer media type mismatch')
            digests.append(entry['digest'])
        require(digests in (diff_ids, [entry['compressedDigest'] for entry in identity['layers']]),
                'Classic scanner manifest layer content mismatch')
        return 'docker-classic-config-and-verified-diff-ids'
    if scanner_manifest_raw == manifest_raw:
        return 'oci-original'
    for representation, digests in [('docker-v2-compressed', [entry['digest'] for entry in manifest['layers']]),
                                    ('docker-v2-diff-ids', diff_ids)]:
        expected = dict(schemaVersion=2, mediaType=DOCKER_MANIFEST,
                        config=dict(mediaType=DOCKER_CONFIG, digest=manifest['config']['digest'], size=manifest['config']['size']),
                        layers=[dict(mediaType=DOCKER_GZIP if entry['mediaType'] == GZIP else DOCKER_TAR,
                                     digest=layer_digest, size=entry['size'])
                                for entry, layer_digest in zip(manifest['layers'], digests)])
        if scanner_manifest == expected:
            return representation
    raise ValueError('Unrecognized scanner manifest conversion')


def safe_members(source):
    members = {}
    for entry in source.getmembers():
        name = entry.name
        require(name not in members, 'Duplicate tar member')
        require(name and '\\' not in name and ':' not in name
                and all(part not in ('', '.', '..') for part in name.rstrip('/').split('/')), 'Unsafe tar path')
        require(entry.isfile() or entry.isdir(), 'Tar links and special members are refused')
        members[name] = entry
    return members


def classic_identity_model(identity, image_id):
    require(identity.get('schemaVersion') == 1 and identity.get('selectedImageId') == image_id
            and identity.get('platform') == 'linux/amd64', 'Classic selected image/platform mismatch')
    sha256(identity['archive']['sha256'])
    integer(identity['archive']['bytes'])
    archive_node = identity['archiveManifest']
    raw = raw64(archive_node.get('rawBase64'))
    require(digest(raw) == archive_node.get('digest') and len(raw) == archive_node.get('size'), 'Classic manifest bytes mismatch')
    records = strict_json(raw)
    require(isinstance(records, list) and len(records) == 1, 'Exactly one classic saved image required')
    config_raw, config = decode_node(identity['config'], CONFIG)
    require(digest(config_raw) == image_id, 'Classic selected ID is not config digest')
    require(config.get('os') == 'linux' and config.get('architecture') == 'amd64'
            and config.get('variant', '') == '', 'Classic config platform mismatch')
    require(config.get('rootfs', {}).get('type') == 'layers', 'Classic rootfs required')
    diff_ids = config['rootfs'].get('diff_ids')
    paths = records[0].get('Layers')
    require(isinstance(diff_ids, list) and isinstance(paths, list) and len(diff_ids) == len(paths) == len(identity['layers']),
            'Classic layer count mismatch')
    manifest_layers = []
    for path, diff_id, layer in zip(paths, diff_ids, identity['layers']):
        sha256(diff_id)
        sha256(layer['compressedDigest'])
        integer(layer['compressedSize'])
        integer(layer['uncompressedSize'])
        require(layer.get('archivePath') == path and layer.get('diffId') == diff_id
                and layer.get('mediaType') in (GZIP, TAR), 'Classic layer proof mismatch')
        manifest_layers.append(dict(mediaType=layer['mediaType'], digest=layer['compressedDigest'], size=layer['compressedSize']))
    if 'archiveLayout' in identity or 'archiveIndex' in identity or 'ociManifest' in identity:
        require(identity.get('archiveLayout') == 'docker-save-oci-dual', 'Unsupported classic archive layout')
        validate_dual_manifest(identity, records[0], config_raw)
    return b'', dict(config=dict(digest=image_id, size=len(config_raw)), layers=manifest_layers), config_raw, diff_ids


def validate_dual_manifest(identity, classic_record, config_raw):
    """Moby classic-store exports also contain a direct-manifest OCI index.

    Its selected Docker ID is the config digest, not an OCI index digest. Both
    archive views must reference the same verified config and ordered layer bytes.
    This is explicit format support, never a fallback after an OCI proof fails.
    """
    _, root = decode_node(identity['archiveIndex'], INDEX)
    require(isinstance(root.get('manifests'), list) and len(root['manifests']) == 1,
            'Dual archive must contain one direct OCI manifest')
    selected = descriptor(root['manifests'][0], MANIFEST)
    manifest_raw, manifest = decode_node(identity['ociManifest'], MANIFEST)
    require(selected['digest'] == digest(manifest_raw) and selected['size'] == len(manifest_raw),
            'Dual OCI manifest descriptor mismatch')
    config = descriptor(manifest.get('config'), CONFIG)
    require(config['digest'] == digest(config_raw) and config['size'] == len(config_raw)
            and classic_record.get('Config') == 'blobs/sha256/' + config['digest'][7:],
            'Dual archive config views disagree')
    layers = manifest.get('layers')
    require(isinstance(layers, list) and len(layers) == len(identity['layers']), 'Dual OCI layer count mismatch')
    for item, layer in zip(layers, identity['layers']):
        descriptor(item)
        require(item.get('mediaType') in (GZIP, TAR) and item['mediaType'] == layer['mediaType']
                and item['digest'] == layer['compressedDigest'] and item['size'] == layer['compressedSize']
                and layer['archivePath'] == 'blobs/sha256/' + item['digest'][7:],
                'Dual archive layer views disagree')


def capture_classic_identity(archive, image_id, platform='linux/amd64'):
    archive = Path(archive)
    sha256(image_id)
    require(platform == 'linux/amd64', 'Only linux/amd64 is approved')
    with archive.open('rb') as stream:
        archive_digest, archive_size = hash_stream(stream)
    with tarfile.open(archive, 'r:') as source:
        members = safe_members(source)

        def read(name):
            require(name in members and members[name].isfile() and members[name].size <= 1024 * 1024,
                    'Missing or oversized classic JSON entry')
            with source.extractfile(members[name]) as stream:
                return stream.read()

        manifest_raw = read('manifest.json')
        records = strict_json(manifest_raw)
        require(isinstance(records, list) and len(records) == 1 and isinstance(records[0], dict),
                'Exactly one classic saved image required')
        config_raw = read(records[0].get('Config'))
        require(digest(config_raw) == image_id, 'Classic config is not selected image ID')
        config = strict_json(config_raw)
        diff_ids = config.get('rootfs', {}).get('diff_ids')
        paths = records[0].get('Layers')
        require(isinstance(diff_ids, list) and isinstance(paths, list) and len(diff_ids) == len(paths),
                'Classic saved layers mismatch')
        layers = []
        for name, expected_diff_id in zip(paths, diff_ids):
            require(name in members and members[name].isfile(), 'Missing regular classic layer')
            with source.extractfile(members[name]) as stream:
                compressed_digest, compressed_size = hash_stream(stream)
            with source.extractfile(members[name]) as stream:
                compressed = stream.read(2) == b'\x1f\x8b'
            with source.extractfile(members[name]) as stream:
                if compressed:
                    with gzip.GzipFile(fileobj=stream) as expanded:
                        actual_diff_id, expanded_size = hash_stream(expanded)
                else:
                    actual_diff_id, expanded_size = hash_stream(stream)
            require(actual_diff_id == sha256(expected_diff_id), 'Classic expanded layer diff_id mismatch')
            layers.append(dict(archivePath=name, mediaType=GZIP if compressed else TAR,
                               compressedDigest=compressed_digest, compressedSize=compressed_size,
                               diffId=actual_diff_id, uncompressedSize=expanded_size))
        dual = {}
        if 'index.json' in members:
            layout = strict_json(read('oci-layout'))
            require(isinstance(layout, dict) and layout.get('imageLayoutVersion') == '1.0.0', 'Unsupported OCI layout')
            root_raw = read('index.json')
            root = strict_json(root_raw)
            require(isinstance(root, dict) and isinstance(root.get('manifests'), list) and len(root['manifests']) == 1,
                    'Dual archive must contain one direct OCI manifest')
            selected = descriptor(root['manifests'][0], MANIFEST)
            manifest_blob = read('blobs/sha256/' + selected['digest'][7:])
            dual = dict(archiveLayout='docker-save-oci-dual', archiveIndex=node(root_raw, INDEX),
                        ociManifest=node(manifest_blob, MANIFEST))
    result = dict(schemaVersion=1, proofType='docker-config-content-chain', selectedImageId=image_id,
                  platform=platform, archive=dict(sha256=archive_digest, bytes=archive_size),
                  archiveManifest=node(manifest_raw, 'docker-save-manifest-v1'), config=node(config_raw, CONFIG), layers=layers,
                  **dual)
    classic_identity_model(result, image_id)
    return result


def capture_identity(archive, image_id, platform='linux/amd64'):
    # Recognize Moby's direct-manifest dual export before the exact-index format.
    # A failed index-based proof never falls back to the config-based verifier.
    with tarfile.open(archive, 'r:') as source:
        members = safe_members(source)
        if 'index.json' in members:
            entry = members['index.json']
            require(entry.isfile() and entry.size <= 1024 * 1024, 'Missing or oversized archive index')
            with source.extractfile(entry) as stream:
                root = strict_json(stream.read())
            require(isinstance(root, dict) and isinstance(root.get('manifests'), list), 'Invalid archive index')
            direct = root['manifests']
            if direct and all(isinstance(item, dict) and item.get('mediaType') == MANIFEST for item in direct):
                require('manifest.json' in members, 'Direct-manifest config-ID archive requires its classic view')
                return capture_classic_identity(archive, image_id, platform)
    if 'index.json' in members:
        return capture_oci_identity(archive, image_id, platform)
    require('manifest.json' in members, 'Unsupported Docker archive format')
    return capture_classic_identity(archive, image_id, platform)
