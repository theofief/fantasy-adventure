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
    #[Route('/ping', name: 'api_ping', methods: ['GET'])]
    public function ping(): JsonResponse
    {
        return $this->json([
            'ok' => true,
            'service' => 'fantasy-adventure-api',
        ]);
    }

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
            ->setGameData(is_array($payload['gameData'] ?? null) ? $this->normalizeGameData($payload['gameData']) : $this->normalizeGameData([]));

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

        /** @var array<string, mixed> $incomingGameData */
        $incomingGameData = $payload['gameData'];
        $incomingGameData = $this->preserveExistingInventoryWhenMissing($incomingGameData, $user->getGameData());
        $user->setGameData($this->normalizeGameData($incomingGameData));
        $entityManager->flush();

        return $this->json(['message' => 'Sauvegarde mise a jour.', 'gameData' => $user->getGameData()]);
    }

    #[Route('/save', name: 'api_save_patch', methods: ['PATCH'])]
    public function patchSave(
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

        $mergedGameData = array_replace_recursive($user->getGameData(), $payload['gameData']);
        $user->setGameData($this->normalizeGameData($mergedGameData));
        $entityManager->flush();

        return $this->json(['message' => 'Sauvegarde fusionnee.', 'gameData' => $user->getGameData()]);
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
            'admin' => $user->isAdmin(),
            'gameData' => $user->getGameData(),
        ];
    }

    /**
     * @param array<mixed> $gameData
     *
     * @return array<mixed>
     */
    private function normalizeGameData(array $gameData): array
    {
        $normalized = $gameData;
        $saveMeta = $normalized['saveMeta'] ?? [];
        if (!is_array($saveMeta)) {
            $saveMeta = [];
        }

        $now = new DateTimeImmutable();
        $saveMeta['serverUpdatedAtIso'] = $now->format(DateTimeInterface::ATOM);
        $saveMeta['schemaVersion'] = (int) ($saveMeta['schemaVersion'] ?? 1);
        $normalized['saveMeta'] = $saveMeta;
        if (isset($normalized['inventory']) && is_array($normalized['inventory'])) {
            $normalized['inventory'] = $this->normalizeInventoryState($normalized['inventory']);
        }

        return $normalized;
    }

    /**
     * @param array<string, mixed> $incomingGameData
     * @param array<string, mixed> $existingGameData
     *
     * @return array<string, mixed>
     */
    private function preserveExistingInventoryWhenMissing(array $incomingGameData, array $existingGameData): array
    {
        $incomingInventory = $incomingGameData['inventory'] ?? null;
        $existingInventory = $existingGameData['inventory'] ?? null;

        if (
            (!is_array($incomingInventory) || $incomingInventory === [])
            && is_array($existingInventory)
            && $existingInventory !== []
        ) {
            $incomingGameData['inventory'] = $existingInventory;
        }

        return $incomingGameData;
    }

    /**
     * @param array<mixed> $inventory
     *
     * @return array<string, mixed>
     */
    private function normalizeInventoryState(array $inventory): array
    {
        $rows = $this->normalizeInventoryRows($inventory);
        $inventorySlots = [];
        for ($rowIndex = 0; $rowIndex < 4; $rowIndex++) {
            for ($columnIndex = 0; $columnIndex < 4; $columnIndex++) {
                $inventorySlots[] = (string) $rows[$rowIndex][$columnIndex];
            }
        }

        $selectedSlotKind = (string) ($inventory['selectedSlotKind'] ?? 'hotbar');
        if (!in_array($selectedSlotKind, ['inventory', 'hotbar'], true)) {
            $selectedSlotKind = 'hotbar';
        }

        $selectedSlotLimit = $selectedSlotKind === 'hotbar' ? 3 : 15;

        return [
            'schemaVersion' => 2,
            'columns' => 4,
            'rowCount' => 5,
            'hotbarRow' => 4,
            'rowLabels' => ['A', 'B', 'C', 'D', 'HOTBAR'],
            'rows' => $rows,
            'inventorySlots' => $inventorySlots,
            'hotbarSlots' => $rows[4],
            'selectedSlot' => max(0, min((int) ($inventory['selectedSlot'] ?? 0), $selectedSlotLimit)),
            'selectedHeldSlot' => max(0, min((int) ($inventory['selectedHeldSlot'] ?? 0), 3)),
            'selectedSlotKind' => $selectedSlotKind,
        ];
    }

    /**
     * @param array<mixed> $inventory
     *
     * @return array<int, array<int, string>>
     */
    private function normalizeInventoryRows(array $inventory): array
    {
        $rawRows = $inventory['rows'] ?? null;
        if (is_array($rawRows) && count($rawRows) >= 5) {
            $rows = [];
            for ($rowIndex = 0; $rowIndex < 5; $rowIndex++) {
                $rows[] = $this->normalizeSlotArray(is_array($rawRows[$rowIndex] ?? null) ? $rawRows[$rowIndex] : [], 4);
            }

            return $rows;
        }

        $inventorySlots = $this->normalizeSlotArray(is_array($inventory['inventorySlots'] ?? null) ? $inventory['inventorySlots'] : [], 16);
        $hotbarSlots = $this->normalizeSlotArray(is_array($inventory['hotbarSlots'] ?? null) ? $inventory['hotbarSlots'] : [], 4);
        if ($this->slotArrayIsEmpty($hotbarSlots) && !in_array('sword', $inventorySlots, true)) {
            $hotbarSlots[0] = 'sword';
        }

        return [
            array_slice($inventorySlots, 0, 4),
            array_slice($inventorySlots, 4, 4),
            array_slice($inventorySlots, 8, 4),
            array_slice($inventorySlots, 12, 4),
            $hotbarSlots,
        ];
    }

    /**
     * @param array<mixed> $slots
     *
     * @return array<int, string>
     */
    private function normalizeSlotArray(array $slots, int $expectedSize): array
    {
        $normalized = array_fill(0, $expectedSize, '');
        for ($index = 0; $index < min(count($slots), $expectedSize); $index++) {
            $normalized[$index] = (string) $slots[$index];
        }

        return $normalized;
    }

    /**
     * @param array<int, string> $slots
     */
    private function slotArrayIsEmpty(array $slots): bool
    {
        foreach ($slots as $slot) {
            if ($slot !== '') {
                return false;
            }
        }

        return true;
    }
}
