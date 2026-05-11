<?php

function xiaoma_hermes_metrics_dir(): string
{
    $env = getenv('XIAOMA_HERMES_STATS_DIR');
    if ($env !== false && $env !== '') {
        return $env;
    }

    $appRoot = realpath(__DIR__ . '/..');
    if ($appRoot === false) {
        $appRoot = dirname(__DIR__);
    }

    return dirname($appRoot) . '/hermes_stats';
}

function xiaoma_hermes_metrics_record(string $event = 'status'): array
{
    $seed = 10000;
    $map = [
        'view' => 'page_views',
        'install' => 'installs',
        'status' => '',
    ];

    if (!array_key_exists($event, $map)) {
        $event = 'status';
    }

    $dir = xiaoma_hermes_metrics_dir();
    if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
        throw new RuntimeException('无法创建统计目录');
    }

    $db = new PDO('sqlite:' . $dir . '/hermes_metrics.sqlite');
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db->exec('PRAGMA busy_timeout = 2000');
    $db->exec('CREATE TABLE IF NOT EXISTS counters (name TEXT PRIMARY KEY, value INTEGER NOT NULL DEFAULT 0)');
    $db->exec('CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        created_at TEXT NOT NULL,
        ip_hash TEXT,
        ua_hash TEXT
    )');

    $insert = $db->prepare('INSERT OR IGNORE INTO counters (name, value) VALUES (:name, :value)');
    foreach (['page_views' => 0, 'installs' => 0, 'seed' => $seed] as $name => $value) {
        $insert->execute([':name' => $name, ':value' => $value]);
    }

    $counter = $map[$event];
    if ($counter !== '') {
        $db->beginTransaction();
        $update = $db->prepare('UPDATE counters SET value = value + 1 WHERE name = :name');
        $update->execute([':name' => $counter]);

        $salt = getenv('XIAOMA_HERMES_STATS_SALT');
        if ($salt === false || $salt === '') {
            $salt = php_uname('n');
        }
        $ip = $_SERVER['REMOTE_ADDR'] ?? '';
        $ua = $_SERVER['HTTP_USER_AGENT'] ?? '';
        $eventInsert = $db->prepare('INSERT INTO events (type, created_at, ip_hash, ua_hash) VALUES (:type, :created_at, :ip_hash, :ua_hash)');
        $eventInsert->execute([
            ':type' => $event,
            ':created_at' => gmdate('c'),
            ':ip_hash' => $ip === '' ? null : hash('sha256', $salt . '|' . $ip),
            ':ua_hash' => $ua === '' ? null : hash('sha256', $salt . '|' . $ua),
        ]);
        $db->commit();
    }

    $rows = $db->query('SELECT name, value FROM counters')->fetchAll(PDO::FETCH_KEY_PAIR);
    $pageViews = (int)($rows['page_views'] ?? 0);
    $installs = (int)($rows['installs'] ?? 0);
    $base = (int)($rows['seed'] ?? $seed);
    $total = $base + $pageViews + $installs;

    return [
        'ok' => true,
        'total' => $total,
        'display' => number_format($total),
    ];
}
