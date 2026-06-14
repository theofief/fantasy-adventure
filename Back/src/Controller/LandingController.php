<?php

declare(strict_types=1);

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
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

        return new Response((string) file_get_contents($indexPath), Response::HTTP_OK, [
            'Content-Type' => 'text/html; charset=UTF-8',
        ]);
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
        }

        return new Response($contents, Response::HTTP_OK, [
            'Content-Type' => $this->guessMimeType($fullPath),
            'Cross-Origin-Resource-Policy' => 'same-origin',
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
}
