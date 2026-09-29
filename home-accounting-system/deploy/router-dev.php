<?php
/**
 * Dev-only front controller for PHP's built-in web server.
 *
 * The upstream service is written for Apache: server/www/.htaccess rewrites
 * every non-file request to index.php, and index.php dispatches on
 * $_SERVER['REDIRECT_URL'], which only Apache's mod_rewrite sets. PHP's
 * built-in server honours neither, so without this shim every request falls
 * through to the empty '' route (the landing page).
 *
 * Usage:
 *   php -S 127.0.0.1:8080 -t server/www deploy/router-dev.php
 *
 * Not for production - use Apache with the shipped .htaccess (or the nginx
 * equivalent described in deploy/README.md).
 */

$docroot = $_SERVER['DOCUMENT_ROOT'];
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);

// Mirror "RewriteCond %{REQUEST_FILENAME} !-f / !-d": serve real files directly.
if ($path !== '/' && is_file($docroot . $path)) {
    return false;
}

$_SERVER['REDIRECT_URL'] = ($path === '/') ? '' : $path;
require $docroot . '/index.php';
