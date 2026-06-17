<?php

/**
 * This file has been auto-generated
 * by the Symfony Routing Component.
 */

return [
    false, // $matchHost
    [ // $staticRoutes
        '/admin' => [[['_route' => 'admin_dashboard', '_controller' => 'App\\Controller\\AdminController::dashboard'], null, ['GET' => 0], null, false, false, null]],
        '/admin/login' => [[['_route' => 'admin_login', '_controller' => 'App\\Controller\\AdminController::login'], null, ['GET' => 0, 'POST' => 1], null, false, false, null]],
        '/admin/logout' => [[['_route' => 'admin_logout', '_controller' => 'App\\Controller\\AdminController::logout'], null, ['POST' => 0, 'GET' => 1], null, false, false, null]],
        '/admin/users' => [[['_route' => 'admin_user_create', '_controller' => 'App\\Controller\\AdminController::createUser'], null, ['POST' => 0], null, false, false, null]],
        '/api/ping' => [[['_route' => 'api_ping', '_controller' => 'App\\Controller\\Api\\AuthController::ping'], null, ['GET' => 0], null, false, false, null]],
        '/api/register' => [[['_route' => 'api_register', '_controller' => 'App\\Controller\\Api\\AuthController::register'], null, ['POST' => 0], null, false, false, null]],
        '/api/login' => [[['_route' => 'api_login', '_controller' => 'App\\Controller\\Api\\AuthController::login'], null, ['POST' => 0], null, false, false, null]],
        '/api/me' => [[['_route' => 'api_me', '_controller' => 'App\\Controller\\Api\\AuthController::me'], null, ['GET' => 0], null, false, false, null]],
        '/api/save' => [
            [['_route' => 'api_save', '_controller' => 'App\\Controller\\Api\\AuthController::save'], null, ['PUT' => 0], null, false, false, null],
            [['_route' => 'api_save_patch', '_controller' => 'App\\Controller\\Api\\AuthController::patchSave'], null, ['PATCH' => 0], null, false, false, null],
        ],
        '/' => [[['_route' => 'landing_index', '_controller' => 'App\\Controller\\LandingController::index'], null, ['GET' => 0], null, false, false, null]],
        '/site.webmanifest' => [[['_route' => 'site_webmanifest', '_controller' => 'App\\Controller\\LandingController::webmanifest'], null, ['GET' => 0], null, false, false, null]],
        '/manifest.webmanifest' => [[['_route' => 'site_webmanifest_alias', '_controller' => 'App\\Controller\\LandingController::webmanifest'], null, ['GET' => 0], null, false, false, null]],
        '/play' => [[['_route' => 'game_web_index', '_controller' => 'App\\Controller\\LandingController::play'], null, ['GET' => 0], null, false, false, null]],
    ],
    [ // $regexpList
        0 => '{^(?'
                .'|/_error/(\\d+)(?:\\.([^/]++))?(*:35)'
                .'|/admin/users/(?'
                    .'|(\\d+)/edit(*:68)'
                    .'|(\\d+)/delete(*:87)'
                    .'|(\\d+)(*:99)'
                .')'
                .'|/play/(.+)(*:117)'
                .'|/((?!api/|_profiler/|_wdt/|play(?:/|$)).+\\.(?:png|jpe?g|gif|webp|svg|ico|css|js|map|json|woff2?|ttf|otf))(*:230)'
            .')/?$}sDu',
    ],
    [ // $dynamicRoutes
        35 => [[['_route' => '_preview_error', '_controller' => 'error_controller::preview', '_format' => 'html'], ['code', '_format'], null, null, false, true, null]],
        68 => [[['_route' => 'admin_user_edit', '_controller' => 'App\\Controller\\AdminController::editUser'], ['id'], ['GET' => 0, 'POST' => 1], null, false, false, null]],
        87 => [[['_route' => 'admin_user_delete', '_controller' => 'App\\Controller\\AdminController::deleteUser'], ['id'], ['POST' => 0], null, false, false, null]],
        99 => [[['_route' => 'admin_user_show', '_controller' => 'App\\Controller\\AdminController::showUser'], ['id'], ['GET' => 0, 'POST' => 1], null, false, true, null]],
        117 => [[['_route' => 'game_web_asset', '_controller' => 'App\\Controller\\LandingController::playAsset'], ['path'], ['GET' => 0], null, false, true, null]],
        230 => [
            [['_route' => 'landing_asset', '_controller' => 'App\\Controller\\LandingController::asset'], ['path'], ['GET' => 0], null, false, true, null],
            [null, null, null, null, false, false, 0],
        ],
    ],
    null, // $checkCondition
];
