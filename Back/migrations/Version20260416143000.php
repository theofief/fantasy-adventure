<?php

declare(strict_types=1);

namespace DoctrineMigrations;

use Doctrine\DBAL\Schema\Schema;
use Doctrine\Migrations\AbstractMigration;

final class Version20260416143000 extends AbstractMigration
{
    public function getDescription(): string
    {
        return 'Add admin flag to users and seed the default admin account.';
    }

    public function up(Schema $schema): void
    {
        $this->addSql('ALTER TABLE users ADD COLUMN admin BOOLEAN NOT NULL DEFAULT 0');
        $this->addSql("UPDATE users SET admin = 0 WHERE admin IS NULL");
        $this->addSql("INSERT OR IGNORE INTO users (email, password, nom, prenom, date_naissance, pseudo, game_data, api_token, admin) VALUES ('admin@fantasy-adventure.local', '" . password_hash('admin1234', PASSWORD_DEFAULT) . "', 'Admin', 'Compte', '2000-01-01', 'admin', '{}', NULL, 1)");
    }

    public function down(Schema $schema): void
    {
        $this->addSql("DELETE FROM users WHERE email = 'admin@fantasy-adventure.local'");
        $this->addSql('ALTER TABLE users DROP COLUMN admin');
    }
}