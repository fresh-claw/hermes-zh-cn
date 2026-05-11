<?php

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, max-age=0');

try {
    require_once __DIR__ . '/metrics_lib.php';
    $event = $_GET['event'] ?? $_POST['event'] ?? 'status';
    $result = xiaoma_hermes_metrics_record((string)$event);
    echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'ok' => false,
        'total' => 10000,
        'display' => '10,000',
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
}

