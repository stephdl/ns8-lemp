<?php
$mariadb = 'not reachable';
try {
    $db = new PDO(
        'mysql:host=' . getenv('LEMP_DB_HOST') . ';port=' . getenv('LEMP_DB_PORT'),
        getenv('LEMP_DB_USER'),
        getenv('LEMP_DB_PASSWORD'),
        [PDO::ATTR_TIMEOUT => 3]
    );
    $mariadb = $db->query('SELECT VERSION()')->fetchColumn();
} catch (Exception $e) {
    $mariadb = 'not reachable: ' . $e->getMessage();
}
$os = @parse_ini_file('/etc/os-release');
?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>NS8 LEMP</title>
    <style>
        body { font-family: sans-serif; max-width: 48rem; margin: 3rem auto; padding: 0 1rem; color: #222; }
        code { background: #f2f2f2; padding: 0 .3rem; }
        td { padding: .2rem 1rem .2rem 0; }
    </style>
</head>
<body>
    <h1>NS8 LEMP is running</h1>
    <p>Replace this page with your application in the <code>/app</code> volume.
       See <a href="https://github.com/stephdl/ns8-lemp#readme">the documentation</a>.</p>
    <table>
        <tr><td>Web server</td><td><?= htmlspecialchars($_SERVER['SERVER_SOFTWARE'] ?? '') ?></td></tr>
        <tr><td>PHP</td><td><?= PHP_VERSION ?></td></tr>
        <tr><td>MariaDB</td><td><?= htmlspecialchars($mariadb) ?></td></tr>
        <tr><td>Database</td><td><?= htmlspecialchars(getenv('LEMP_DB_NAME') ?: '') ?></td></tr>
        <tr><td>PHP container OS</td><td><?= htmlspecialchars($os['PRETTY_NAME'] ?? '') ?></td></tr>
    </table>
    <p>Delete <code>index.php</code> once your application is installed.</p>
</body>
</html>
