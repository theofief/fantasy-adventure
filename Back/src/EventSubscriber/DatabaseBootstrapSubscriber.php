<?php

declare(strict_types=1);

namespace App\EventSubscriber;

use Doctrine\DBAL\Connection;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\KernelEvents;

final class DatabaseBootstrapSubscriber implements EventSubscriberInterface
{
    private bool $bootstrapped = false;

    public function __construct(private readonly Connection $connection)
    {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            KernelEvents::REQUEST => ['onKernelRequest', 50],
        ];
    }

    public function onKernelRequest(RequestEvent $event): void
    {
        if (!$event->isMainRequest() || $this->bootstrapped) {
            return;
        }

        $this->bootstrapped = true;

        $this->ensureAdminSchema();
        $this->ensureDefaultAdminAccount();
    }

    private function ensureAdminSchema(): void
    {
        if (!$this->tableExists('users')) {
            return;
        }

        if ($this->columnExists('users', 'admin')) {
            return;
        }

        $this->connection->executeStatement('ALTER TABLE users ADD COLUMN admin BOOLEAN NOT NULL DEFAULT 0');
    }

    private function ensureDefaultAdminAccount(): void
    {
        if (!$this->tableExists('users') || !$this->columnExists('users', 'admin')) {
            return;
        }

        $email = 'admin@fantasy-adventure.local';
        $pseudo = 'admin';
        $passwordHash = password_hash('admin1234', PASSWORD_DEFAULT);

        $existingId = $this->connection->fetchOne('SELECT id FROM users WHERE email = :email LIMIT 1', [
            'email' => $email,
        ]);

        if ($existingId === false) {
            $pseudoConflict = $this->connection->fetchOne('SELECT id FROM users WHERE pseudo = :pseudo LIMIT 1', [
                'pseudo' => $pseudo,
            ]);

            if ($pseudoConflict !== false) {
                $pseudo = 'admin_root';
            }

            $this->connection->executeStatement(
                'INSERT INTO users (email, password, nom, prenom, date_naissance, pseudo, game_data, api_token, admin) VALUES (:email, :password, :nom, :prenom, :dateNaissance, :pseudo, :gameData, NULL, 1)',
                [
                    'email' => $email,
                    'password' => $passwordHash,
                    'nom' => 'Admin',
                    'prenom' => 'Compte',
                    'dateNaissance' => '2000-01-01',
                    'pseudo' => $pseudo,
                    'gameData' => '{}',
                ]
            );

            return;
        }

        $this->connection->executeStatement(
            'UPDATE users SET admin = 1 WHERE email = :email',
            ['email' => $email]
        );
    }

    private function tableExists(string $tableName): bool
    {
        $result = $this->connection->fetchOne(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = :name LIMIT 1",
            ['name' => $tableName]
        );

        return $result !== false;
    }

    private function columnExists(string $tableName, string $columnName): bool
    {
        $columns = $this->connection->fetchAllAssociative('PRAGMA table_info('.$tableName.')');
        foreach ($columns as $column) {
            if (isset($column['name']) && $column['name'] === $columnName) {
                return true;
            }
        }

        return false;
    }
}