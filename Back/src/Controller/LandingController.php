<?php

declare(strict_types=1);

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\Routing\Attribute\Route;

final class LandingController extends AbstractController
{
    #[Route('/', name: 'landing_index', methods: ['GET'])]
    public function index(): Response
    {
        $projectRoot = dirname($this->getParameter('kernel.project_dir'));
        $indexPath = $projectRoot.'/index.html';

        if (!is_file($indexPath)) {
            throw new NotFoundHttpException('Fichier index.html introuvable a la racine du projet.');
        }

        $contents = $this->injectPwaHead((string) file_get_contents($indexPath));

        return new Response($contents, Response::HTTP_OK, [
            'Content-Type' => 'text/html; charset=UTF-8',
        ]);
    }

    #[Route('/site.webmanifest', name: 'site_webmanifest', methods: ['GET'])]
    #[Route('/manifest.webmanifest', name: 'site_webmanifest_alias', methods: ['GET'])]
    public function webmanifest(): JsonResponse
    {
        $response = new JsonResponse([
            'id' => '/play',
            'name' => 'Fantasy Adventure',
            'short_name' => 'Fantasy',
            'description' => 'RPG pixel art jouable dans le navigateur avec sauvegarde, exploration, combats et inventaire.',
            'lang' => 'fr',
            'dir' => 'ltr',
            'start_url' => '/play',
            'scope' => '/',
            'display' => 'fullscreen',
            'display_override' => ['fullscreen', 'standalone', 'minimal-ui'],
            'orientation' => 'any',
            'background_color' => '#0d0d1a',
            'theme_color' => '#f7d94c',
            'categories' => ['games', 'entertainment', 'role-playing'],
            'prefer_related_applications' => false,
            'icons' => [
                [
                    'src' => '/play/index.144x144.png',
                    'sizes' => '144x144',
                    'type' => 'image/png',
                    'purpose' => 'any',
                ],
                [
                    'src' => '/play/index.180x180.png',
                    'sizes' => '180x180',
                    'type' => 'image/png',
                    'purpose' => 'any',
                ],
                [
                    'src' => '/play/index.512x512.png',
                    'sizes' => '512x512',
                    'type' => 'image/png',
                    'purpose' => 'any maskable',
                ],
            ],
            'shortcuts' => [
                [
                    'name' => 'Jouer',
                    'short_name' => 'Jouer',
                    'description' => 'Lancer Fantasy Adventure directement.',
                    'url' => '/play',
                    'icons' => [
                        [
                            'src' => '/play/index.144x144.png',
                            'sizes' => '144x144',
                            'type' => 'image/png',
                        ],
                    ],
                ],
                [
                    'name' => 'Panel admin',
                    'short_name' => 'Admin',
                    'description' => 'Consulter et modifier les sauvegardes des joueurs.',
                    'url' => '/admin',
                    'icons' => [
                        [
                            'src' => '/play/index.144x144.png',
                            'sizes' => '144x144',
                            'type' => 'image/png',
                        ],
                    ],
                ],
            ],
            'screenshots' => [
                [
                    'src' => '/background-image.png',
                    'sizes' => '600x337',
                    'type' => 'image/png',
                    'form_factor' => 'wide',
                    'label' => 'Fantasy Adventure - monde pixel art',
                ],
                [
                    'src' => '/play/index.png',
                    'sizes' => '800x600',
                    'type' => 'image/png',
                    'form_factor' => 'narrow',
                    'label' => 'Fantasy Adventure - ecran de lancement',
                ],
            ],
        ]);

        $response->headers->set('Content-Type', 'application/manifest+json; charset=UTF-8');
        $response->headers->set('Cache-Control', 'no-cache');

        return $response;
    }

    #[Route('/play', name: 'game_web_index', methods: ['GET'])]
    public function play(): Response
    {
        return $this->servePlayFile('index.html');
    }

    #[Route(
        '/play/{path}',
        name: 'game_web_asset',
        methods: ['GET'],
        requirements: ['path' => '.+'],
    )]
    public function playAsset(string $path): Response
    {
        return $this->servePlayFile($path);
    }

    #[Route(
        '/{path}',
        name: 'landing_asset',
        methods: ['GET'],
        requirements: ['path' => '(?!api/|_profiler/|_wdt/|play(?:/|$)).+\.(?:png|jpe?g|gif|webp|svg|ico|css|js|map|json|woff2?|ttf|otf)$'],
        priority: -100,
    )]
    public function asset(string $path): Response
    {
        $projectRoot = dirname($this->getParameter('kernel.project_dir'));
        $fullPath = realpath($projectRoot.'/'.$path);

        if (
            $fullPath === false
            || !str_starts_with($fullPath, $projectRoot.DIRECTORY_SEPARATOR)
            || !is_file($fullPath)
        ) {
            throw new NotFoundHttpException('Asset introuvable.');
        }

        return new Response((string) file_get_contents($fullPath), Response::HTTP_OK, [
            'Content-Type' => $this->guessMimeType($fullPath),
        ]);
    }

    private function servePlayFile(string $path): Response
    {
        $projectDir = $this->getParameter('kernel.project_dir');
        $playRoot = realpath($projectDir.'/var/play');
        if ($playRoot === false) {
            throw new NotFoundHttpException('Build Web du jeu introuvable. Lancez l export Godot Web avant d ouvrir /play.');
        }

        $fullPath = realpath($playRoot.'/'.$path);

        if (
            $fullPath === false
            || !str_starts_with($fullPath, $playRoot.DIRECTORY_SEPARATOR)
            || !is_file($fullPath)
        ) {
            throw new NotFoundHttpException('Build Web du jeu introuvable. Lancez l export Godot Web avant d ouvrir /play.');
        }

        $contents = (string) file_get_contents($fullPath);
        if (strtolower((string) pathinfo($fullPath, PATHINFO_EXTENSION)) === 'html') {
            $contents = str_replace('<head>', '<head><base href="/play/">', $contents);
            $contents = $this->injectPwaHead($contents);
        }

        return new Response($contents, Response::HTTP_OK, [
            'Content-Type' => $this->guessMimeType($fullPath),
            'Cross-Origin-Resource-Policy' => 'same-origin',
            'Permissions-Policy' => 'autoplay=(self), fullscreen=(self), gamepad=(self)',
            'Cache-Control' => 'no-cache',
        ]);
    }

    private function guessMimeType(string $fullPath): string
    {
        $extension = strtolower((string) pathinfo($fullPath, PATHINFO_EXTENSION));

        return match ($extension) {
            'png' => 'image/png',
            'jpg', 'jpeg' => 'image/jpeg',
            'gif' => 'image/gif',
            'webp' => 'image/webp',
            'svg' => 'image/svg+xml',
            'ico' => 'image/x-icon',
            'html' => 'text/html; charset=UTF-8',
            'css' => 'text/css; charset=UTF-8',
            'js' => 'application/javascript; charset=UTF-8',
            'wasm' => 'application/wasm',
            'pck' => 'application/octet-stream',
            'json' => 'application/json; charset=UTF-8',
            'map' => 'application/json; charset=UTF-8',
            'woff' => 'font/woff',
            'woff2' => 'font/woff2',
            'ttf' => 'font/ttf',
            'otf' => 'font/otf',
            default => 'application/octet-stream',
        };
    }

    private function injectPwaHead(string $html): string
    {
        if (str_contains($html, 'rel="manifest"')) {
            return $html;
        }

        $pwaHead = <<<'HTML'
  <link rel="manifest" href="/site.webmanifest">
  <meta name="application-name" content="Fantasy Adventure">
  <meta name="apple-mobile-web-app-title" content="Fantasy Adventure">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="theme-color" content="#f7d94c">
  <link rel="apple-touch-icon" sizes="180x180" href="/play/index.180x180.png">
  <link rel="icon" type="image/png" sizes="144x144" href="/play/index.144x144.png">
  <link rel="icon" type="image/png" sizes="512x512" href="/play/index.512x512.png">
HTML;

        return str_replace('</head>', $pwaHead."\n</head>", $html);
    }
}
