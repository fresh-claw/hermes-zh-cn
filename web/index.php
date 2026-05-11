<?php

$total = null;

try {
    require_once __DIR__ . '/api/metrics_lib.php';
    $metrics = xiaoma_hermes_metrics_record('view');
    $total = $metrics['total'] ?? null;
} catch (Throwable $e) {
    $total = null;
}

$html = file_get_contents(__DIR__ . '/index.html');
if ($html === false) {
    http_response_code(500);
    exit('index.html missing');
}

$totalJson = json_encode($total, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
$inject = '<script>window.__XIAOMA_HERMES_VIEW_RECORDED__=true;window.__XIAOMA_HERMES_METRIC_TOTAL__=' . $totalJson . ';</script>';

echo str_replace('</head>', $inject . "\n  </head>", $html);

