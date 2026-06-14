<?php

declare(strict_types=1);

namespace App\Controller;

use App\Entity\User;
use App\Repository\UserRepository;
use DateTimeImmutable;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;
use Symfony\Component\Routing\Attribute\Route;

#[Route('/admin')]
final class AdminController extends AbstractController
{
    #[Route('', name: 'admin_dashboard', methods: ['GET'])]
    public function dashboard(Request $request, UserRepository $userRepository): Response
    {
        $adminUser = $this->requireAdminUser($request, $userRepository);
        if ($adminUser === null) {
            return $this->redirectToRoute('admin_login');
        }

        $users = $userRepository->findBy([], ['id' => 'ASC']);
        $notice = $this->consumeSessionMessage($request, 'admin_notice');
        $error = $this->consumeSessionMessage($request, 'admin_error');

        $csrfToken = $this->getAdminCsrfToken($request);

        return new Response($this->renderDashboardPage($adminUser, $users, $notice, $error, $csrfToken));
    }

    #[Route('/login', name: 'admin_login', methods: ['GET', 'POST'])]
    public function login(
        Request $request,
        UserRepository $userRepository,
        UserPasswordHasherInterface $passwordHasher,
    ): Response {
        $existingAdmin = $this->requireAdminUser($request, $userRepository);
        if ($existingAdmin !== null) {
            return $this->redirectToRoute('admin_dashboard');
        }

        $error = '';
        if ($request->isMethod('POST')) {
            $email = mb_strtolower(trim($request->request->getString('email')));
            $password = $request->request->getString('password');

            if ($email === '' || $password === '') {
                $error = 'Email et mot de passe requis.';
            } else {
                $user = $userRepository->findOneBy(['email' => $email]);
                if ($user === null || !$passwordHasher->isPasswordValid($user, $password) || !$user->isAdmin()) {
                    $error = 'Acces admin refuse.';
                } else {
                    $request->getSession()->set('admin_user_id', $user->getId());
                    // create a per-session CSRF token for admin forms
                    $request->getSession()->set('admin_csrf_token', bin2hex(random_bytes(32)));
                    $request->getSession()->set('admin_notice', 'Connexion admin reussie.');

                    return $this->redirectToRoute('admin_dashboard');
                }
            }
        }

        return new Response($this->renderLoginPage($error));
    }

    #[Route('/logout', name: 'admin_logout', methods: ['POST', 'GET'])]
    public function logout(Request $request): Response
    {
        // if logout via POST, verify CSRF
        if ($request->isMethod('POST') && !$this->verifyAdminCsrf($request)) {
            $request->getSession()->set('admin_error', 'Jeton CSRF invalide.');

            return $this->redirectToRoute('admin_dashboard');
        }

        $session = $request->getSession();
        $session->remove('admin_user_id');
        $session->set('admin_notice', 'Deconnexion admin effectuee.');

        return $this->redirectToRoute('admin_login');
    }

    #[Route('/users', name: 'admin_user_create', methods: ['POST'])]
    public function createUser(
        Request $request,
        UserRepository $userRepository,
        EntityManagerInterface $entityManager,
        UserPasswordHasherInterface $passwordHasher,
    ): Response {
        $adminUser = $this->requireAdminUser($request, $userRepository);
        if ($adminUser === null) {
            return $this->redirectToRoute('admin_login');
        }

        if (!$this->verifyAdminCsrf($request)) {
            $request->getSession()->set('admin_error', 'Jeton CSRF invalide.');

            return $this->redirectToRoute('admin_dashboard');
        }

        [$error, $user] = $this->buildUserFromRequest($request, $userRepository, $passwordHasher);
        if ($error !== '' || $user === null) {
            $request->getSession()->set('admin_error', $error !== '' ? $error : 'Creation impossible.');

            return $this->redirectToRoute('admin_dashboard');
        }

        $entityManager->persist($user);
        $entityManager->flush();
        $request->getSession()->set('admin_notice', 'Utilisateur cree.');

        return $this->redirectToRoute('admin_dashboard');
    }

    #[Route('/users/{id}/edit', name: 'admin_user_edit', requirements: ['id' => '\\d+'], methods: ['GET', 'POST'])]
    public function editUser(
        int $id,
        Request $request,
        UserRepository $userRepository,
        EntityManagerInterface $entityManager,
        UserPasswordHasherInterface $passwordHasher,
    ): Response {
        $adminUser = $this->requireAdminUser($request, $userRepository);
        if ($adminUser === null) {
            return $this->redirectToRoute('admin_login');
        }

        $user = $userRepository->find($id);
        if (!$user instanceof User) {
            $request->getSession()->set('admin_error', 'Utilisateur introuvable.');

            return $this->redirectToRoute('admin_dashboard');
        }

        $error = '';
        if ($request->isMethod('POST')) {
            if (!$this->verifyAdminCsrf($request)) {
                $request->getSession()->set('admin_error', 'Jeton CSRF invalide.');

                return $this->redirectToRoute('admin_dashboard');
            }
            $email = mb_strtolower(trim($request->request->getString('email')));
            $nom = trim($request->request->getString('nom'));
            $prenom = trim($request->request->getString('prenom'));
            $dateNaissanceValue = trim($request->request->getString('dateNaissance'));
            $pseudo = trim($request->request->getString('pseudo'));
            $password = $request->request->getString('password');
            $isAdmin = $request->request->has('admin');

            $error = $this->validateUserPayload($email, $nom, $prenom, $dateNaissanceValue, $pseudo, $userRepository, $user);
            if ($error === '') {
                $user->setEmail($email)
                    ->setNom($nom)
                    ->setPrenom($prenom)
                    ->setDateNaissance(new DateTimeImmutable($dateNaissanceValue))
                    ->setPseudo($pseudo)
                    ->setAdmin($isAdmin);

                if ($password !== '') {
                    $user->setPassword($passwordHasher->hashPassword($user, $password));
                }

                $entityManager->flush();
                $request->getSession()->set('admin_notice', 'Utilisateur mis a jour.');

                return $this->redirectToRoute('admin_dashboard');
            }
        }

        $csrfToken = $this->getAdminCsrfToken($request);

        return new Response($this->renderEditPage($adminUser, $user, $error, $csrfToken));
    }

    #[Route('/users/{id}/delete', name: 'admin_user_delete', requirements: ['id' => '\\d+'], methods: ['POST'])]
    public function deleteUser(
        int $id,
        Request $request,
        UserRepository $userRepository,
        EntityManagerInterface $entityManager,
    ): Response {
        $adminUser = $this->requireAdminUser($request, $userRepository);
        if ($adminUser === null) {
            return $this->redirectToRoute('admin_login');
        }

        $user = $userRepository->find($id);
        if (!$user instanceof User) {
            $request->getSession()->set('admin_error', 'Utilisateur introuvable.');

            return $this->redirectToRoute('admin_dashboard');
        }

        if ($adminUser->getId() === $user->getId()) {
            $request->getSession()->set('admin_error', 'Tu ne peux pas supprimer ton propre compte admin.');

            return $this->redirectToRoute('admin_dashboard');
        }

        if (!$this->verifyAdminCsrf($request)) {
            $request->getSession()->set('admin_error', 'Jeton CSRF invalide.');

            return $this->redirectToRoute('admin_dashboard');
        }

        $entityManager->remove($user);
        $entityManager->flush();
        $request->getSession()->set('admin_notice', 'Utilisateur supprime.');

        return $this->redirectToRoute('admin_dashboard');
    }

    #[Route('/users/{id}', name: 'admin_user_show', requirements: ['id' => '\\d+'], methods: ['GET', 'POST'])]
    public function showUser(
        int $id,
        Request $request,
        UserRepository $userRepository,
        EntityManagerInterface $entityManager,
    ): Response {
        $adminUser = $this->requireAdminUser($request, $userRepository);
        if ($adminUser === null) {
            return $this->redirectToRoute('admin_login');
        }

        $user = $userRepository->find($id);
        if (!$user instanceof User) {
            $request->getSession()->set('admin_error', 'Utilisateur introuvable.');

            return $this->redirectToRoute('admin_dashboard');
        }

        $csrfToken = $this->getAdminCsrfToken($request);
        $error = '';
        $notice = '';

        if ($request->isMethod('POST')) {
            if (!$this->verifyAdminCsrf($request)) {
                $error = 'Jeton CSRF invalide.';
            } else {
                $rawGameData = trim($request->request->getString('gameData'));
                if ($rawGameData === '') {
                    $rawGameData = '{}';
                }

                try {
                    $decodedGameData = json_decode($rawGameData, true, 512, JSON_THROW_ON_ERROR);
                    if (!is_array($decodedGameData)) {
                        $error = 'La sauvegarde doit etre un objet JSON.';
                    } else {
                        $user->setGameData($decodedGameData);
                        $entityManager->flush();
                        $notice = 'Sauvegarde joueur mise a jour.';
                    }
                } catch (\JsonException $exception) {
                    $error = 'JSON invalide: '.$exception->getMessage();
                }
            }
        }

        return new Response($this->renderUserDetailPage($adminUser, $user, $csrfToken, $notice, $error));
    }

    private function requireAdminUser(Request $request, UserRepository $userRepository): ?User
    {
        $session = $request->getSession();
        $adminUserId = $session->get('admin_user_id');
        if (!is_int($adminUserId) && !ctype_digit((string) $adminUserId)) {
            return null;
        }

        $user = $userRepository->find((int) $adminUserId);
        if (!$user instanceof User || !$user->isAdmin()) {
            $session->remove('admin_user_id');

            return null;
        }

        return $user;
    }

    private function consumeSessionMessage(Request $request, string $key): string
    {
        $value = $request->getSession()->remove($key);

        return is_string($value) ? $value : '';
    }

    /**
     * @return array{0:string,1:?User}
     */
    private function buildUserFromRequest(
        Request $request,
        UserRepository $userRepository,
        UserPasswordHasherInterface $passwordHasher,
    ): array {
        $email = mb_strtolower(trim($request->request->getString('email')));
        $password = $request->request->getString('password');
        $nom = trim($request->request->getString('nom'));
        $prenom = trim($request->request->getString('prenom'));
        $dateNaissanceValue = trim($request->request->getString('dateNaissance'));
        $pseudo = trim($request->request->getString('pseudo'));
        $isAdmin = $request->request->has('admin');

        $error = $this->validateUserPayload($email, $nom, $prenom, $dateNaissanceValue, $pseudo, $userRepository, null);
        if ($error !== '') {
            return [$error, null];
        }

        if ($password === '') {
            return ['Le mot de passe est obligatoire pour creer un compte.', null];
        }

        $user = (new User())
            ->setEmail($email)
            ->setNom($nom)
            ->setPrenom($prenom)
            ->setDateNaissance(new DateTimeImmutable($dateNaissanceValue))
            ->setPseudo($pseudo)
            ->setAdmin($isAdmin)
            ->setGameData([]);

        $user->setPassword($passwordHasher->hashPassword($user, $password));
        $user->setApiToken(null);

        return ['', $user];
    }

    private function validateUserPayload(
        string $email,
        string $nom,
        string $prenom,
        string $dateNaissanceValue,
        string $pseudo,
        UserRepository $userRepository,
        ?User $currentUser,
    ): string {
        if ($email === '' || $nom === '' || $prenom === '' || $dateNaissanceValue === '' || $pseudo === '') {
            return 'Tous les champs obligatoires doivent etre remplis.';
        }

        $dateNaissance = DateTimeImmutable::createFromFormat('Y-m-d', $dateNaissanceValue);
        if (!$dateNaissance instanceof DateTimeImmutable) {
            return 'Date invalide. Format attendu: YYYY-MM-DD.';
        }

        $existingEmailUser = $userRepository->findOneBy(['email' => $email]);
        if ($existingEmailUser instanceof User && ($currentUser === null || $existingEmailUser->getId() !== $currentUser->getId())) {
            return 'Cet email est deja utilise.';
        }

        $existingPseudoUser = $userRepository->findOneBy(['pseudo' => $pseudo]);
        if ($existingPseudoUser instanceof User && ($currentUser === null || $existingPseudoUser->getId() !== $currentUser->getId())) {
            return 'Ce pseudo est deja utilise.';
        }

        return '';
    }

    /**
     * @param array<int, User> $users
     */
    private function renderDashboardPage(User $adminUser, array $users, string $notice, string $error, string $csrfToken): string
    {
        $userRows = '';
        foreach ($users as $user) {
            $adminBadge = $user->isAdmin()
                ? '<span class="badge badge-admin">Admin</span>'
                : '<span class="badge badge-user">User</span>';
            $gameDataSize = count($user->getGameData());
            $userRows .= sprintf(
                '<tr>
                    <td>%s</td>
                    <td>%s</td>
                    <td>%s</td>
                    <td>%s</td>
                    <td>%s</td>
                    <td>%s</td>
                    <td>%s</td>
                    <td>
                        <a class="action-link action-link-secondary" href="/admin/users/%d">Voir la sauvegarde</a>
                        <a class="action-link" href="/admin/users/%d/edit">Modifier</a>
                        <form method="post" action="/admin/users/%d/delete" onsubmit="return confirm(\'Supprimer cet utilisateur ?\');">
                            <input type="hidden" name="admin_csrf" value="%s">
                            <button type="submit" class="danger">Supprimer</button>
                        </form>
                    </td>
                </tr>',
                $this->e((string) $user->getId()),
                $this->e($user->getEmail()),
                $this->e($user->getPseudo()),
                $this->e($user->getDateNaissance()->format('Y-m-d')),
                $adminBadge,
                $this->e((string) $gameDataSize),
                $this->e($user->getApiToken() ?? '—'),
                $user->getId(),
                $user->getId(),
                $user->getId(),
                $this->e($csrfToken),
            );
        }

        $content = sprintf(
            '<div class="layout">
                <section class="hero-card">
                    <div class="eyebrow">Administration</div>
                    <h1>Bonjour, %s</h1>
                    <p>Gere les comptes de Fantasy Adventure depuis cette interface web.</p>
                    <div class="stats">
                        <div class="stat"><span>%d</span><small>comptes</small></div>
                        <div class="stat"><span>%d</span><small>admins</small></div>
                        <div class="stat"><span>%d</span><small>joueurs</small></div>
                    </div>
                    <form method="post" action="/admin/logout">
                        <input type="hidden" name="admin_csrf" value="%s">
                        <button type="submit" class="secondary">Deconnexion</button>
                    </form>
                </section>

                <section class="panel">
                    <h2>Creer un compte</h2>
                    <form method="post" action="/admin/users" class="form-grid">
                        <input type="hidden" name="admin_csrf" value="%s">
                        <label>Email<input type="email" name="email" required></label>
                        <label>Mot de passe<input type="password" name="password" required></label>
                        <label>Nom<input type="text" name="nom" required></label>
                        <label>Prenom<input type="text" name="prenom" required></label>
                        <label>Date de naissance<input type="date" name="dateNaissance" required></label>
                        <label>Pseudo<input type="text" name="pseudo" required></label>
                        <label class="checkbox"><input type="checkbox" name="admin"> Compte admin</label>
                        <button type="submit">Creer le compte</button>
                    </form>
                </section>

                <section class="panel table-panel">
                    <div class="panel-head">
                        <h2>Comptes existants</h2>
                        <p>%d comptes affiches</p>
                    </div>
                    <div class="table-wrap">
                        <table>
                            <thead>
                                <tr>
                                    <th>ID</th><th>Email</th><th>Pseudo</th><th>Date naissance</th><th>Role</th><th>Save gameData</th><th>Token</th><th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>%s</tbody>
                        </table>
                    </div>
                </section>
            </div>',
            $this->e($adminUser->getPseudo() !== '' ? $adminUser->getPseudo() : $adminUser->getEmail()),
            count($users),
            count(array_filter($users, static fn (User $user): bool => $user->isAdmin())),
            count(array_filter($users, static fn (User $user): bool => !$user->isAdmin())),
            count($users),
            $this->e($csrfToken),
            $this->e($csrfToken),
            $userRows,
        );

        return $this->wrapPage('Admin Fantasy Adventure', $content, $notice, $error, '/admin/login');
    }

    private function renderUserDetailPage(User $adminUser, User $user, string $csrfToken, string $notice, string $error): string
    {
        $gameData = $user->getGameData();
        $bindings = $this->extractInputBindings($gameData);
        $bindingsMeta = $this->extractInputBindingsMeta($gameData);
        $progress = $this->extractProgressSummary($gameData);
        $playerSummary = $this->extractPlayerSummary($gameData);
        $settingsSummary = $this->extractSettingsSummary($gameData);

        $bindingsHtml = '';
        foreach ($bindings as $actionName => $slots) {
            $bindingsHtml .= sprintf(
                '<tr><td><code>%s</code></td><td>%s</td><td>%s</td></tr>',
                $this->e((string) $actionName),
                $this->e((string) ($slots[0] ?? '--')),
                $this->e((string) ($slots[1] ?? '--')),
            );
        }

        if ($bindingsHtml === '') {
            $bindingsHtml = '<tr><td colspan="3">Aucune touche enregistrée pour cette sauvegarde.</td></tr>';
        }

        $content = sprintf(
            '<div class="layout layout-single layout-detail">
                <section class="hero-card">
                    <div class="eyebrow">Sauvegarde joueur</div>
                    <h1>%s</h1>
                    <p>Consulte et modifie la sauvegarde JSON stockee en base pour ce joueur.</p>
                    <a class="secondary link-button" href="/admin">Retour au dashboard</a>
                </section>

                <section class="panel detail-panel">
                    <div class="detail-grid">
                        <div class="detail-card"><span>Email</span><strong>%s</strong></div>
                        <div class="detail-card"><span>Pseudo</span><strong>%s</strong></div>
                        <div class="detail-card"><span>Role</span><strong>%s</strong></div>
                        <div class="detail-card"><span>Naissance</span><strong>%s</strong></div>
                        <div class="detail-card"><span>Derniere sauvegarde</span><strong>%s</strong></div>
                        <div class="detail-card"><span>Position joueur</span><strong>%s</strong></div>
                        <div class="detail-card"><span>Parametres</span><strong>%s</strong></div>
                    </div>

                    <div class="detail-block">
                        <h2>Avancement</h2>
                        <p>%s</p>
                    </div>

                    <div class="detail-block">
                        <h2>Touches enregistrees</h2>
                        <div class="table-wrap">
                            <table>
                                <thead>
                                    <tr><th>Action</th><th>Touche 1</th><th>Touche 2</th></tr>
                                </thead>
                                <tbody>%s</tbody>
                            </table>
                        </div>
                    </div>

                    <div class="detail-block">
                        <h2>Sauvegarde JSON</h2>
                        <form method="post" class="save-json-form">
                            <input type="hidden" name="admin_csrf" value="%s">
                            <textarea name="gameData" spellcheck="false">%s</textarea>
                            <button type="submit">Enregistrer la sauvegarde</button>
                        </form>
                    </div>
                </section>
            </div>',
            $this->e($user->getPseudo() !== '' ? $user->getPseudo() : $user->getEmail()),
            $this->e($user->getEmail()),
            $this->e($user->getPseudo()),
            $user->isAdmin() ? 'Admin' : 'User',
            $this->e($user->getDateNaissance()->format('Y-m-d')),
            $this->e($this->formatBindingsTimestamp($bindingsMeta)),
            $this->e($playerSummary),
            $this->e($settingsSummary),
            $this->e($progress),
            $bindingsHtml,
            $this->e($csrfToken),
            $this->e($this->prettyPrintJson($gameData)),
        );

        return $this->wrapPage('Sauvegarde joueur', $content, $notice, $error, '/admin');
    }

    private function renderEditPage(User $adminUser, User $user, string $error, string $csrfToken): string
    {
        $content = sprintf(
            '<div class="layout layout-single">
                <section class="hero-card">
                    <div class="eyebrow">Edition utilisateur</div>
                    <h1>%s</h1>
                    <p>Modifie le compte sans casser les donnees existantes.</p>
                    <a class="secondary link-button" href="/admin">Retour au dashboard</a>
                </section>

                <section class="panel">
                    <form method="post" class="form-grid">
                        <input type="hidden" name="admin_csrf" value="%s">
                        <label>Email<input type="email" name="email" value="%s" required></label>
                        <label>Nouveau mot de passe<input type="password" name="password" placeholder="Laisser vide pour conserver"></label>
                        <label>Nom<input type="text" name="nom" value="%s" required></label>
                        <label>Prenom<input type="text" name="prenom" value="%s" required></label>
                        <label>Date de naissance<input type="date" name="dateNaissance" value="%s" required></label>
                        <label>Pseudo<input type="text" name="pseudo" value="%s" required></label>
                        <label class="checkbox"><input type="checkbox" name="admin" %s> Compte admin</label>
                        <button type="submit">Enregistrer</button>
                    </form>
                </section>
            </div>',
            $this->e($user->getPseudo()),
            $this->e($csrfToken),
            $this->e($user->getEmail()),
            $this->e($user->getNom()),
            $this->e($user->getPrenom()),
            $this->e($user->getDateNaissance()->format('Y-m-d')),
            $this->e($user->getPseudo()),
            $user->isAdmin() ? 'checked' : '',
        );

        return $this->wrapPage('Edition utilisateur', $content, '', $error, '/admin');
    }

    private function renderLoginPage(string $error): string
    {
        $content = '<div class="layout layout-login">
            <section class="hero-card hero-login">
                <div class="eyebrow">Acces prive</div>
                <h1>Interface admin</h1>
                <p>Connecte-toi avec un compte administrateur pour gerer les comptes joueurs.</p>
            </section>

            <section class="panel login-panel">
                <form method="post" class="form-grid login-form">
                    <label>Email<input type="email" name="email" required></label>
                    <label>Mot de passe<input type="password" name="password" required></label>
                    <button type="submit">Se connecter</button>
                </form>
            </section>
        </div>';

        return $this->wrapPage('Connexion admin', $content, '', $error, '/');
    }

    private function wrapPage(string $title, string $content, string $notice, string $error, string $backLink): string
    {
        $noticeHtml = $notice !== '' ? '<div class="alert alert-notice">'.$this->e($notice).'</div>' : '';
        $errorHtml = $error !== '' ? '<div class="alert alert-error">'.$this->e($error).'</div>' : '';
                $safeTitle = $this->e($title);

                return <<<HTML
<!doctype html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{$safeTitle}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Press+Start+2P&family=Nunito:wght@400;600;700;800&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100%; }
    body {
      font-family: Nunito, sans-serif;
      color: #fff8e7;
            background:
                radial-gradient(circle at top left, rgba(247,217,76,.22), transparent 28%),
                radial-gradient(circle at bottom right, rgba(94,207,232,.18), transparent 26%),
                linear-gradient(180deg, #17172b, #0f1020 58%, #0a0b18);
      padding: 32px;
    }
    a { color: inherit; }
    .layout { display: grid; grid-template-columns: 360px 1fr; gap: 24px; max-width: 1400px; margin: 0 auto; align-items: start; }
    .layout-single { grid-template-columns: 360px 1fr; }
    .layout-login { grid-template-columns: 1fr 1fr; max-width: 1120px; min-height: calc(100vh - 64px); align-items: center; }
    .layout-detail { grid-template-columns: 360px 1fr; }
    .layout-detail .detail-panel { grid-column: 1 / -1; }
    .hero-card, .panel {
      border: 4px solid #f7d94c;
      background: rgba(17,18,34,.86);
      box-shadow: 10px 10px 0 rgba(0,0,0,.35);
      border-radius: 22px;
      padding: 28px;
      backdrop-filter: blur(8px);
    }
    .hero-card h1, .panel h2 {
            font-family: "Press Start 2P", monospace;
      line-height: 1.5;
    }
    .hero-card h1 { font-size: clamp(20px, 2.7vw, 34px); margin: 0 0 14px; }
    .panel h2 { font-size: 16px; margin: 0 0 18px; }
    .eyebrow {
      display: inline-flex; align-items: center; gap: 8px;
            font-family: "Press Start 2P", monospace;
      font-size: 10px; color: #1a1a2e; background: #f7d94c;
      padding: 9px 12px; border: 3px solid #1a1a2e; margin-bottom: 18px;
      box-shadow: 4px 4px 0 rgba(0,0,0,.35);
    }
    .hero-card p { line-height: 1.7; color: #ddeeff; }
    .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 24px 0; }
    .stat { background: rgba(255,255,255,.06); border: 2px solid rgba(247,217,76,.55); border-radius: 18px; padding: 14px; text-align: center; }
    .stat span { display: block; font-size: 28px; font-weight: 800; color: #f7d94c; }
    .stat small { color: #ddeeff; }
    .secondary, button {
      display: inline-flex; align-items: center; justify-content: center; width: 100%;
      border-radius: 14px; border: none; cursor: pointer; padding: 14px 18px;
            font-family: "Press Start 2P", monospace; font-size: 11px; text-decoration: none;
      transition: transform .12s ease, box-shadow .12s ease, filter .12s ease;
    }
    button, .primary {
      color: #1a1a2e; background: #f7d94c; box-shadow: 5px 5px 0 rgba(0,0,0,.35);
    }
    .secondary { color: #fff8e7; background: transparent; border: 3px solid #fff8e7; box-shadow: 4px 4px 0 rgba(255,255,255,.15); }
    button:hover, .secondary:hover, .action-link:hover { transform: translate(-2px,-2px); }
    .link-button { display: inline-flex; width: auto; margin-top: 16px; }
    .alert {
      max-width: 1400px; margin: 0 auto 18px; padding: 14px 18px; border-radius: 14px;
      border: 2px solid; font-weight: 700; box-shadow: 6px 6px 0 rgba(0,0,0,.2);
    }
    .alert-notice { background: rgba(106,191,75,.18); border-color: #6abf4b; }
    .alert-error { background: rgba(255,105,105,.15); border-color: #ff6969; }
    .form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
    .form-grid label { display: flex; flex-direction: column; gap: 8px; color: #ddeeff; font-weight: 700; }
    .form-grid input {
      background: rgba(255,255,255,.08); color: #fff8e7; border: 2px solid rgba(247,217,76,.45);
      border-radius: 12px; padding: 14px; font: inherit;
    }
    .form-grid input:focus { outline: none; border-color: #f7d94c; box-shadow: 0 0 0 4px rgba(247,217,76,.16); }
    .checkbox { grid-column: 1 / -1; flex-direction: row !important; align-items: center; }
    .checkbox input { width: 18px; height: 18px; }
    .login-panel, .hero-login { display: flex; flex-direction: column; justify-content: center; min-height: 340px; }
    .login-form { max-width: 420px; margin: 0 auto; }
    .login-panel button { grid-column: 1 / -1; }
    .table-panel { grid-column: 1 / -1; overflow: hidden; }
    .panel-head { display: flex; justify-content: space-between; gap: 16px; align-items: end; margin-bottom: 16px; }
    .panel-head p { margin: 0; color: #ddeeff; }
    .table-wrap { overflow: auto; border-radius: 16px; border: 2px solid rgba(247,217,76,.25); }
    table { width: 100%; border-collapse: collapse; min-width: 980px; }
    th, td { padding: 14px 12px; text-align: left; vertical-align: top; border-bottom: 1px solid rgba(255,255,255,.08); }
    th { position: sticky; top: 0; background: #121322; color: #f7d94c; font-family: "Press Start 2P", monospace; font-size: 9px; }
    td code { color: #f7d94c; }
    td form { display: inline-block; margin: 0 0 0 8px; }
    .action-link, .danger {
      display: inline-flex; align-items: center; justify-content: center; border-radius: 10px; padding: 10px 12px;
      text-decoration: none; font-weight: 800; border: 2px solid transparent;
    }
    .action-link { background: rgba(94,207,232,.16); border-color: rgba(94,207,232,.35); }
        .action-link-secondary { background: rgba(255,255,255,.08); border-color: rgba(255,255,255,.18); }
    .danger { width: auto; background: rgba(255,105,105,.15); color: #fff8e7; border-color: rgba(255,105,105,.5); font-family: inherit; }
    .badge { display: inline-flex; align-items: center; justify-content: center; padding: 6px 10px; border-radius: 999px; font-size: 12px; font-weight: 800; }
    .badge-admin { background: rgba(247,217,76,.18); color: #f7d94c; border: 1px solid rgba(247,217,76,.4); }
    .badge-user { background: rgba(255,255,255,.08); color: #ddeeff; border: 1px solid rgba(255,255,255,.16); }
        .detail-grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 14px;
            margin-bottom: 20px;
        }
        .detail-card {
            background: rgba(255,255,255,.06);
            border: 2px solid rgba(247,217,76,.28);
            border-radius: 16px;
            padding: 14px;
        }
        .detail-card span {
            display: block;
            color: #ddeeff;
            font-size: 12px;
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .detail-card strong {
            display: block;
            color: #fff8e7;
            font-size: 16px;
            word-break: break-word;
        }
        .detail-block {
            margin-top: 18px;
            padding-top: 18px;
            border-top: 1px solid rgba(255,255,255,.08);
        }
        .detail-block h2 { margin-bottom: 12px; }
        .detail-block p { margin: 0; line-height: 1.7; color: #ddeeff; }
        .detail-block pre {
            margin: 0;
            padding: 18px;
            border-radius: 16px;
            overflow: auto;
            background: rgba(10,11,24,.85);
            border: 1px solid rgba(247,217,76,.18);
            color: #cfe9ff;
            font-size: 13px;
            line-height: 1.6;
            white-space: pre-wrap;
            word-break: break-word;
        }
        .save-json-form {
            display: grid;
            gap: 14px;
        }
        .save-json-form textarea {
            min-height: 420px;
            width: 100%;
            resize: vertical;
            padding: 18px;
            border-radius: 16px;
            background: rgba(10,11,24,.85);
            border: 1px solid rgba(247,217,76,.3);
            color: #cfe9ff;
            font: 13px/1.6 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            white-space: pre;
        }
        .save-json-form textarea:focus {
            outline: none;
            border-color: #f7d94c;
            box-shadow: 0 0 0 4px rgba(247,217,76,.16);
        }
    @media (max-width: 1080px) { .layout, .layout-login { grid-template-columns: 1fr; } .login-panel, .hero-login { min-height: auto; } }
        @media (max-width: 720px) { body { padding: 16px; } .form-grid { grid-template-columns: 1fr; } .stats { grid-template-columns: 1fr; } .detail-grid { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
    {$noticeHtml}
    {$errorHtml}
    {$content}
</body>
</html>
HTML;
    }

    private function e(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    private function getAdminCsrfToken(Request $request): string
    {
        $session = $request->getSession();
        $token = $session->get('admin_csrf_token');
        if (!is_string($token) || $token === '') {
            $token = bin2hex(random_bytes(32));
            $session->set('admin_csrf_token', $token);
        }

        return $token;
    }

    private function verifyAdminCsrf(Request $request): bool
    {
        $token = $request->request->getString('admin_csrf', '');
        $session = $request->getSession();
        $sess = $session->get('admin_csrf_token', '');

        if (!is_string($token) || !is_string($sess) || $token === '' || $sess === '') {
            return false;
        }

        return hash_equals($sess, $token);
    }

    /**
     * @return array<string, array<int, string>>
     */
    private function extractInputBindings(array $gameData): array
    {
        $bindings = $gameData['inputBindings'] ?? [];
        if (!is_array($bindings)) {
            return [];
        }

        $normalized = [];
        foreach ($bindings as $actionName => $slots) {
            if (!is_string($actionName) || !is_array($slots)) {
                continue;
            }

            $normalized[$actionName] = [
                $this->formatSerializedInputEvent($slots[0] ?? null),
                $this->formatSerializedInputEvent($slots[1] ?? null),
            ];
        }

        ksort($normalized);

        return $normalized;
    }

    /**
     * @return array{updatedAtUnixMs:int, updatedAtIso:string}
     */
    private function extractInputBindingsMeta(array $gameData): array
    {
        $meta = $gameData['inputBindingsMeta'] ?? [];
        if (!is_array($meta)) {
            return ['updatedAtUnixMs' => 0, 'updatedAtIso' => ''];
        }

        return [
            'updatedAtUnixMs' => (int) ($meta['updatedAtUnixMs'] ?? 0),
            'updatedAtIso' => (string) ($meta['updatedAtIso'] ?? ''),
        ];
    }

    private function extractProgressSummary(array $gameData): string
    {
        if ($gameData === []) {
            return 'Aucune progression enregistree pour le moment.';
        }

        $worldState = $gameData['worldState'] ?? [];
        if (!is_array($worldState)) {
            return 'Donnees disponibles: '.implode(', ', array_map('strval', array_keys($gameData))).'.';
        }

        $coins = (int) ($worldState['coins'] ?? 0);
        $hp = (int) ($worldState['hp'] ?? 0);
        $maxHp = (int) ($worldState['maxHp'] ?? 0);
        $slimesKilled = (int) ($worldState['slimesKilled'] ?? 0);
        $deadEnemies = $worldState['deadEnemies'] ?? [];
        $deadEnemiesCount = is_array($deadEnemies) ? count($deadEnemies) : 0;

        return sprintf(
            'Pieces: %d. Vie: %d/%d. Slimes tues: %d. Ennemis morts memorises: %d.',
            $coins,
            $hp,
            $maxHp,
            $slimesKilled,
            $deadEnemiesCount,
        );
    }

    private function prettyPrintJson(array $data): string
    {
        $encoded = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

        return is_string($encoded) ? $encoded : '{}';
    }

    private function formatBindingsTimestamp(array $bindingsMeta): string
    {
        $unixMs = (int) ($bindingsMeta['updatedAtUnixMs'] ?? 0);
        $iso = trim((string) ($bindingsMeta['updatedAtIso'] ?? ''));

        if ($unixMs <= 0 && $iso === '') {
            return 'Aucune date de sauvegarde disponible';
        }

        if ($iso !== '') {
            return $iso;
        }

        return (string) $unixMs;
    }

    private function extractPlayerSummary(array $gameData): string
    {
        $playerState = $gameData['playerState'] ?? [];
        if (!is_array($playerState)) {
            return 'Aucune position sauvegardee';
        }

        $scene = (string) ($playerState['scenePath'] ?? 'scene inconnue');
        $position = $playerState['position'] ?? [];
        if (!is_array($position)) {
            return $scene;
        }

        return sprintf(
            '%s (x: %s, y: %s)',
            $scene,
            (string) ($position['x'] ?? '?'),
            (string) ($position['y'] ?? '?'),
        );
    }

    private function extractSettingsSummary(array $gameData): string
    {
        $settings = $gameData['settings'] ?? [];
        if (!is_array($settings)) {
            return 'Aucun parametre sauvegarde';
        }

        $locale = (string) ($settings['locale'] ?? 'n/a');
        $autoReconnect = (bool) ($settings['autoReconnect'] ?? false);

        return sprintf('Langue: %s. Reconnexion auto: %s.', $locale, $autoReconnect ? 'oui' : 'non');
    }

    private function formatSerializedInputEvent(mixed $event): string
    {
        if (is_string($event) && $event !== '') {
            return $event;
        }

        if (!is_array($event)) {
            return '--';
        }

        $parts = [];
        foreach (['ctrl_pressed' => 'Ctrl', 'alt_pressed' => 'Alt', 'shift_pressed' => 'Shift', 'meta_pressed' => 'Meta'] as $key => $label) {
            if ((bool) ($event[$key] ?? false)) {
                $parts[] = $label;
            }
        }

        $keyCode = (int) ($event['physical_keycode'] ?? 0);
        if ($keyCode <= 0) {
            $keyCode = (int) ($event['keycode'] ?? 0);
        }

        $parts[] = $keyCode > 0 ? (string) $keyCode : '?';

        return implode(' + ', $parts);
    }
}
