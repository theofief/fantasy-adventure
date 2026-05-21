<?php

namespace App\DataFixtures;

use App\Entity\User;
use Doctrine\Bundle\FixturesBundle\Fixture;
use Doctrine\Persistence\ObjectManager;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;

class AppFixtures extends Fixture
{
    public function __construct(
        private UserPasswordHasherInterface $passwordHasher
    ) {}

    public function load(ObjectManager $manager): void
    {
        $admin = new User();

        $admin->setEmail('admin@game.com');
        $admin->setPseudo('admin');
        $admin->setNom('Admin');
        $admin->setPrenom('Root');
        $admin->setDateNaissance(new \DateTimeImmutable('2000-01-01'));
        $admin->setGameData([]);

        $admin->setAdmin(true);

        $admin->setPassword(
            $this->passwordHasher->hashPassword($admin, 'admin123')
        );

        $manager->persist($admin);
        $manager->flush();
    }
}