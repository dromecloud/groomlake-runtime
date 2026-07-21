<?php
declare(strict_types=1);

/**
 * Public Groomlake Runtime ATIS (Automated Terminal Information Service).
 *
 * This endpoint is deliberately read-only: it exposes only the repository
 * manifest and accepts no file paths, commands, or write operations.
 */

const MANIFEST_MAX_BYTES = 1024 * 1024;

function manifest_fail(int $status): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, max-age=0');
    header('X-Content-Type-Options: nosniff');
    echo json_encode(['error' => 'manifest_unavailable'], JSON_UNESCAPED_SLASHES);
    exit;
}

$method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));
if (!in_array($method, ['GET', 'HEAD'], true)) {
    header('Allow: GET, HEAD');
    manifest_fail(405);
}

$manifest_path = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'manifest.json';
if (!is_file($manifest_path) || !is_readable($manifest_path)) {
    manifest_fail(503);
}

$size = filesize($manifest_path);
if ($size === false || $size < 2 || $size > MANIFEST_MAX_BYTES) {
    manifest_fail(503);
}

$raw = file_get_contents($manifest_path);
if ($raw === false || strlen($raw) !== $size) {
    manifest_fail(503);
}

$manifest = json_decode($raw, true);
if (!is_array($manifest)
    || ($manifest['schema_version'] ?? null) !== 2
    || !is_string($manifest['manifest_version'] ?? null)
    || !preg_match('/^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$/', $manifest['manifest_version'])
    || !is_array($manifest['runtime'] ?? null)
    || ($manifest['runtime']['id'] ?? null) !== 'groomlake-runtime'
    || !is_array($manifest['profiles'] ?? null)
    || !is_array($manifest['components'] ?? null)) {
    manifest_fail(503);
}

$sha256 = hash('sha256', $raw);
$etag = '"' . $sha256 . '"';
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');
header('ETag: ' . $etag);
header('X-Groomlake-Manifest-Version: ' . $manifest['manifest_version']);

$commit_path = __DIR__ . DIRECTORY_SEPARATOR . 'commit.txt';
if (is_file($commit_path) && is_readable($commit_path)) {
    $commit = trim((string) file_get_contents($commit_path));
    if (preg_match('/^[0-9a-f]{40}$/', $commit) === 1) {
        header('X-Groomlake-Commit: ' . $commit);
    }
}

if (($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) {
    http_response_code(304);
    exit;
}

if ($method === 'HEAD') {
    exit;
}

echo $raw;
