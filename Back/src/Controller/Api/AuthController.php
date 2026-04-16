<?php

declare(strict_types=1);

namespace App\Controller\Api;

use App\Entity\User;
use App\Repository\UserRepository;
use DateTimeImmutable;
use DateTimeInterface;
use Doctrine\ORM\EntityManagerInterface;
use JsonException;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;
use Symfony\Component\Routing\Attribute\Route;

#[Route('/api')]
class AuthController extends AbstractController
{
    #[Route('/register', name: 'api_register', methods: ['POST'])]
    public function register(
        Request $request,
        UserRepository $userRepository,
        UserPasswordHasherInterface $passwordHasher,
        EntityManagerInterface $entityManager,
    ): JsonResponse {
        try {
            /** @var array<string, mixed> $payload */
            $payload = json_decode($request->getContent(), true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            return $this->json(['error' => 'JSON invalide.'], JsonResponse::HTTP_BAD_REQUEST);
        }

        $requiredFields = ['email', 'password', 'nom', 'prenom', 'dateNaissance', 'pseudo'];
        foreach ($requiredFields as $field) {
            if (!isset($payload[$field]) || !is_string($payload[$field]) || trim($payload[$field]) === '') {
                return $this->json(['error' => sprintf('Champ obligatoire manquant: %s', $field)], JsonResponse::HTTP_BAD_REQUEST);
            }
        }

        if ($userRepository->findOneBy(['email' => mb_strtolower(trim((string) $payload['email']))]) !== null) {
            return $this->json(['error' => 'Cet email est deja utilise.'], JsonResponse::HTTP_CONFLICT);
        }

        if ($userRepository->findOneBy(['pseudo' => trim((string) $payload['pseudo'])]) !== null) {
            return $this->json(['error' => 'Ce pseudo est deja utilise.'], JsonResponse::HTTP_CONFLICT);
        }

        $dateNaissance = DateTimeImmutable::createFromFormat('Y-m-d', (string) $payload['dateNaissance']);
        if (!$dateNaissance instanceof DateTimeImmutable) {
            return $this->json(['error' => 'Format de date invalide, attendu: YYYY-MM-DD'], JsonResponse::HTTP_BAD_REQUEST);
        }

        $user = (new User())
            ->setEmail((string) $payload['email'])
            ->setNom((string) $payload['nom'])
            ->setPrenom((string) $payload['prenom'])
            ->setDateNaissance($dateNaissance)
            ->setPseudo((string) $payload['pseudo'])
            ->setGameData(is_array($payload['gameData'] ?? null) ? $payload['gameData'] : []);

        $user->setPassword($passwordHasher->hashPassword($user, (string) $payload['password']));
        $user->setApiToken(bin2hex(random_bytes(32)));

        $entityManager->persist($user);
        $entityManager->flush();

        return $this->json([
            'id' => $user->getId(),
            'token' => $user->getApiToken(),
            'user' => $this->serializeUser($user),
        ], JsonResponse::HTTP_CREATED);
    }

    #[Route('/login', name: 'api_login', methods: ['POST'])]
    public function login(
        Request $request,
        UserRepository $userRepository,
        UserPasswordHasherInterface $passwordHasher,
        EntityManagerInterface $entityManager,
    ): JsonResponse {
        try {
            /** @var array<string, mixed> $payload */
            $payload = json_decode($request->getContent(), true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            return $this->json(['error' => 'JSON invalide.'], JsonResponse::HTTP_BAD_REQUEST);
        }

        $email = mb_strtolower(trim((string) ($payload['email'] ?? '')));
        $password = (string) ($payload['password'] ?? '');

        if ($email === '' || $password === '') {
            return $this->json(['error' => 'Email et mot de passe requis.'], JsonResponse::HTTP_BAD_REQUEST);
        }

        $user = $userRepository->findOneBy(['email' => $email]);
        if ($user === null || !$passwordHasher->isPasswordValid($user, $password)) {
            return $this->json(['error' => 'Identifiants invalides.'], JsonResponse::HTTP_UNAUTHORIZED);
        }

        $user->setApiToken(bin2hex(random_bytes(32)));
        $entityManager->flush();

        return $this->json([
            'token' => $user->getApiToken(),
            'user' => $this->serializeUser($user),
        ]);
    }

    #[Route('/me', name: 'api_me', methods: ['GET'])]
    public function me(Request $request, UserRepository $userRepository): JsonResponse
    {
        $user = $this->getUserFromToken($request, $userRepository);
        if ($user === null) {
            return $this->json(['error' => 'Token invalide ou manquant.'], JsonResponse::HTTP_UNAUTHORIZED);
        }

        return $this->json($this->serializeUser($user));
    }

    #[Route('/save', name: 'api_save', methods: ['PUT'])]
    public function save(
        Request $request,
        UserRepository $userRepository,
        EntityManagerInterface $entityManager,
    ): JsonResponse {
        $user = $this->getUserFromToken($request, $userRepository);
        if ($user === null) {
            return $this->json(['error' => 'Token invalide ou manquant.'], JsonResponse::HTTP_UNAUTHORIZED);
        }

        try {
            /** @var array<string, mixed> $payload */
            $payload = json_decode($request->getContent(), true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            return $this->json(['error' => 'JSON invalide.'], JsonResponse::HTTP_BAD_REQUEST);
        }

        if (!isset($payload['gameData']) || !is_array($payload['gameData'])) {
            return $this->json(['error' => 'Le champ gameData (JSON objet/tableau) est requis.'], JsonResponse::HTTP_BAD_REQUEST);
        }

        $user->setGameData($payload['gameData']);
        $entityManager->flush();

        return $this->json(['message' => 'Sauvegarde mise a jour.', 'gameData' => $user->getGameData()]);
    }

    private function getUserFromToken(Request $request, UserRepository $userRepository): ?User
    {
        $header = $request->headers->get('Authorization', '');
        if (!str_starts_with($header, 'Bearer ')) {
            return null;
        }

        $token = trim(substr($header, 7));
        if ($token === '') {
            return null;
        }

        return $userRepository->findOneByApiToken($token);
    }

    /**
     * @return array<string, mixed>
     */
    private function serializeUser(User $user): array
    {
        return [
            'id' => $user->getId(),
            'email' => $user->getEmail(),
            'nom' => $user->getNom(),
            'prenom' => $user->getPrenom(),
            'dateNaissance' => $user->getDateNaissance()->format(DateTimeInterface::ATOM),
            'pseudo' => $user->getPseudo(),
            'gameData' => $user->getGameData(),
        ];
    }
}
