# MÉDITRA — Conception complète du back-end Laravel et intégration du front (prompt v6)

Tu es un ingénieur Laravel senior. Tu construis **de zéro** le back-end complet de **MÉDITRA** (MÉdailles et DIstinctions du TRAvail), la plateforme de gestion des médailles et diplômes du travail du Ministère du Travail du Gabon, puis tu y intègres le front fourni en **Blade + JavaScript natif**.

Ce prompt remplace tous les prompts précédents (`prompt_agent_laravel_distinctions`, `prompt_agent_tous_les_lots`, `prompt_agent_back_v5`). **Il n'y a pas de dépôt existant à reprendre** : tu crées un nouveau projet Laravel vierge.

---

## 0. Mode de travail

1. **Tu exécutes toi-même** : tu as un terminal, PHP, Composer, Node et MySQL. Tu lances les migrations, les tests et les outils de qualité, et tu lis leurs résultats réels. Tu n'écris jamais « corrigé » ou « vert » sans l'avoir exécuté.
2. **Une seule exécution continue**, de l'étape 0 à l'étape 9 (section 8), sans t'arrêter pour demander une validation. Quand une décision manque, tu appliques la valeur par défaut (section 11 et section 26 des règles), tu la consignes dans `docs/DECISIONS.md` et tu la remontes dans le rapport final parmi les « hypothèses à valider ».
3. **Seules les opérations dangereuses s'arrêtent** : toute commande destructive sur une base qui n'est pas explicitement la base de test jetable est refusée ; tu la consignes et tu continues le reste.
4. À la fin de chaque étape : tests de l'étape verts, `docs/AVANCEMENT.md` à jour (état, commandes lancées, résultats collés), **un commit** (Git initialisé dès l'étape 1, branche `main`, commits petits et lisibles). Aucun push ni déploiement.
5. Si un test échoue après des tentatives sérieuses : état réel de la fonctionnalité (section 13), cause dans `docs/AVANCEMENT.md`, et tu continues avec ce qui n'en dépend pas.
6. Le seul message attendu à la fin est le **rapport final** (section 12).

---

## 1. Ce que je te fournis (lis dans cet ordre)

| Fichier | Rôle | Autorité |
|---|---|---|
| `02_regles_back_v2.0.md` | **Toutes les règles métier** : profils, permissions, machine à états, dépôt, instruction, paiement, remise, cérémonie, documents, notifications, statistiques, codes d'erreur, extensions de schéma autorisées, questions ouvertes avec valeurs par défaut. | **Fait foi pour le métier.** |
| `03_sql/distinctions_nationales_v4.sql` | Schéma de départ (47 tables, 12 vues, 6 déclencheurs, données de référence). Lis son en-tête. | Fait foi pour le modèle de données… |
| `03_sql/migration_v5_depuis_v4.sql` | Migration v4 → v5 (testée sur MariaDB 10.11 : 52 tables, 14 vues, 8 déclencheurs). | … une fois appliquée après la v4. |
| `03_sql/seed_pays_complet_v4.sql` | Liste complète des pays et nationalités (libellés français) + mise à jour du Gabon. | Seule source du référentiel des pays. |
| `04_front/` | 42 pages HTML/CSS/JS autonomes (8 profils) + `meditra-connexion.html` (connexion, inscription, OTP), `chargement.html` (écran après connexion), `profil-test.html` (page de référence de la charte), `index.html` (catalogue de démonstration). Données **fictives** en mémoire et en `localStorage`. | Fait foi pour **l'apparence**, pas pour les données. |

Ordre d'autorité en cas de conflit : **règles v2.0** > **SQL (v4 + v5 + extensions autorisées)** > **front**. Le front s'adapte au back, jamais l'inverse (section 6.3).

Si un fichier cité manque, ne le devine pas : consigne l'absence et continue.

---

## 2. Stack imposée

- **Laravel** : dernière version stable au démarrage (12.x ou 13.x) et la version de PHP qu'elle exige (≥ 8.2). Indique les versions exactes dans le rapport.
- **MySQL 8.0.16 ou plus** (InnoDB, `utf8mb4_unicode_ci`) : les `CHECK` ne s'appliquent qu'à partir de 8.0.16. Base applicative `meditra`, base de test `meditra_test`.
- **Blade + JavaScript natif.** Pas de React, Vue, Livewire, Inertia, Alpine ni Tailwind. Vite uniquement pour assembler le CSS et le JS natif. **Aucun CDN** : polices DM Serif Display et Manrope hébergées localement (licence OFL), icônes = sprite SVG du front.
- Authentification par **session** (garde `web`), CSRF sur toute écriture. Pas de Sanctum.
- File d'attente et cache en base (`database`) ; mail configurable par `.env` (pilote `log` en local).
- PDF : `barryvdh/laravel-dompdf`, après vérification du rendu réel d'un document (liste avec exemple d'ordre, ordre, délégation, diplôme).
- Tests : **Pest** sur MySQL (jamais SQLite) ; tests de navigateur avec Playwright (ou Laravel Dusk) pour les pages converties.
- Qualité : Laravel Pint ; Larastan niveau 6 minimum, sans exclusion générale.
- Fuseau `Africa/Libreville`, langue `fr`, devise **FCFA** (constante de configuration unique).

N'ajoute aucun autre paquet sans justification écrite dans `docs/DECISIONS.md` (nom, raison, alternative écartée).

---

## 3. Principes

1. **Architecture** (RG-ARCH) : Route → Controller mince → FormRequest → Action (`execute()`, un cas d'usage) → Modèles. Policies pour les autorisations, enums PHP pour chaque ENUM SQL, événements et écouteurs pour notifications, journal et compteurs statistiques. **Seul `DossierWorkflow` écrit `dossier.statut`.**
2. **Pas d'invention.** Ni donnée, ni page, ni permission, ni statut absent des règles. Si une question n'est pas tranchée et n'a pas de valeur par défaut : option la plus prudente et la plus réversible (état vide, fonctionnalité « Bloquée », réglage configurable), consignée comme hypothèse.
3. **Explique tes choix** dans `docs/DECISIONS.md` : « Contexte, choix, alternative écartée, conséquence ».
4. **Le SQL fait foi** ; les seuls écarts permis sont les extensions E1 à E8 (règles, section 24), chacune en migration séparée. Les valeurs d'ENUM ne se modifient jamais pour faire correspondre un écran.
5. **Chaque règle a un test** dont le nom contient son ID (`it('RG-PAY-11 …')`). Une règle sans test n'est pas terminée.
6. **Sécurité d'abord** : mots de passe hachés, aucune route interne sans session et sans permission, fichiers hors du dossier public, aucun secret dans le dépôt, aucune donnée de démonstration hors `local` et `testing`.
7. **Le profil vient du serveur.** Aucun sélecteur de profil, aucune lecture de rôle depuis le navigateur.
8. **Fidélité visuelle** : le front fourni est la référence visuelle. Tu le convertis, tu ne le redessines pas (section 6).

---

## 4. Base de données

### 4.1 Migrations
- Reconstruis le schéma **v4** en migrations Laravel (une par table, dans l'ordre des dépendances), puis la **migration v5** en migrations additives ordonnées, une par groupe **V1 à V10** (en-tête du fichier v5). Respecte exactement noms, types, nullabilité, valeurs par défaut, index, uniques, FK (`RESTRICT` partout sauf la cascade sur `instruction_dossier.dossier_id`).
- Clés naturelles conservées (`stock_distinction`, `tarif`, `ligne_commande`, `distinction_demandee`, `remise_ligne`, `ceremonie_proposition_recipiendaire`).
- ENUM SQL = ENUM MySQL dans la migration + enum PHP. Les nouveaux ENUM obligatoires de la v5 sont `NULL` + `CHECK IS NOT NULL` : garde ce mécanisme (RG-ARCH-11).
- `CHECK`, colonnes générées `STORED` (`uq_signature_un_actif`, `uq_delegation_active`, `uq_prop_ouverte`, `uq_brouillon_actif`) : `DB::statement`.
- **8 déclencheurs** (`trg_js_no_update`, `trg_js_no_delete`, `trg_hd_no_update`, `trg_hd_no_delete`, `trg_dn_verrou`, `trg_medaille_anti_doublon`, `trg_delegation_dr_seul`, `trg_ordre_chef_seul`) : `DB::unprepared`, supprimés dans `down()`. Ne les remplace pas par du code ; ajoute le code applicatif **en plus** pour des erreurs lisibles (RG-ARCH-06).
- **14 vues** (`v_decoration`, 11 `v_stat_*`, `v_dossier_reste_a_remettre`, `v_dossier_bilan`) : migrations dédiées.
- La migration v5 contient des `UPDATE` de reprise de données : sur une base vierge ils n'affectent aucune ligne ; garde-les pour la fidélité et documente-le.
- Extensions **E1 à E8** des règles (section 24) : une migration additive chacune, après V10. E3 (versions de quittance) suit la question ouverte Q7 : applique la valeur par défaut et isole-la dans sa propre migration pour pouvoir la retirer.

### 4.2 Seeders
- **Référence** (tous environnements) : stocks OR/ARGENT/BRONZE, tarifs (20 000 / 15 000 / 13 000 / 3 000), `assistant_ia`, 9 provinces, 13 secteurs, **249 pays et nationalités** chargés depuis `03_sql/seed_pays_complet_v4.sql` (idempotent, conflit de libellé signalé, RG-ADM-02 ; ne recopie ni ne complète la liste à la main), campagne de l'année en cours avec les dates par défaut **uniquement si aucune campagne n'existe**.
- **Premier administrateur** : commande Artisan interactive `meditra:admin` (aucun mot de passe en dur).
- **Démonstration** (`local` et `testing` seulement, refus ailleurs) : un compte par profil (DEMANDEUR entreprise, DEMANDEUR ministère, SECRETARIAT, MINISTRE, DGT, DR, AGENT, CHEF_SERVICE, REGISSEUR, ADMINISTRATEUR) et des dossiers à chaque statut, construits **en passant par les Actions** (jamais d'insertion directe qui contournerait les règles). Une factory par modèle.

### 4.3 Sécurité des opérations et vérification du schéma
- Jamais de `migrate:fresh`, `migrate:refresh`, `db:wipe` ni de suppression massive hors de `meditra_test`. Avant toute opération destructive : affiche environnement, connexion et nom de base ; en cas de doute, refuse. Garde dans `TestCase` et dans les commandes : refus si la base n'est pas `*_test` (RG-ARCH-10).
- **Rapport de différences** du schéma reconstruit par rapport à la référence (v4 exécutée puis v5, dans une base temporaire `meditra_ref_test`) : tables, colonnes, types, défauts, nullabilité, index, uniques, FK, CHECK, colonnes générées, déclencheurs, vues, données de référence. Sépare : écarts réels, extensions autorisées, différences sans conséquence (ordre, noms générés).
- Déclencheurs, CHECK et uniques générées **vérifiés par des tests exécutés sur MySQL** (indique la version).

---

## 5. Domaine

Tout le métier est dans `02_regles_back_v2.0.md`. Points d'implémentation :

- **Modèles** : un par table, `$fillable` explicite, `casts`, toutes les relations déduites des FK, scopes utiles. `Utilisateur` est le modèle d'authentification (`login` = e-mail, `mot_de_passe_hash`) avec `estInterne()`, `estDemandeur()`, `profil()` (renvoie l'un des 9 profils). Les tables techniques et de jonction sont documentées comme telles.
- **Permissions** : `config/permissions.php` = la matrice 3.2 des règles, telle quelle ; une policy par modèle sensible ; un test par ligne de matrice (autorisé et refusé). Étendue de visibilité : RG-DROIT-05.
- **`DossierWorkflow`** : table des transitions T1 à T13, refus de tout le reste (`ETAT_TRANSITION_INTERDITE`), historique dans la même transaction, événement `DossierTransitionne` pour les notifications et compteurs.
- **Erreurs** : `RegleMetierException(code, statut, champs)` ; rendu JSON `{code, message, champs}` pour les appels `fetch`, et rendu Blade (erreur à côté du champ, ou toast) pour les formulaires. Conversion des erreurs SQL de déclencheur en `*_VIOLATION_BASE`.
- **Configuration** `config/distinctions.php` : seuils, réglage `exiger_demandeur_reconnu`, durée des codes, durée de session, taille des pièces, lignes d'import, seuil de stock, rafraîchissement des notifications (30 s), formats de numéros.
- **Notifications** : RG-NOTIF ; base de données + e-mail en file ; statut d'envoi distinct (« en file », « envoyé », « échec »).
- **Statistiques** : un service par vue `v_stat_*` ; aucune agrégation dans les contrôleurs ou le JavaScript ; état vide si aucune ligne.
- **Documents** : disque privé, contrôleur de téléchargement qui vérifie le droit et journalise ; PDF générés depuis Blade ; journal de signature chaîné avec commande `meditra:journal-verifier`.

---

## 6. Front : conversion en Blade

### 6.1 Ce que contiennent les pages fournies
- Chaque fichier HTML est **autonome** : styles intégrés (identiques sur toutes les pages, la charte du profil test), un sprite SVG d'icônes, l'interface (menu latéral vert, barre du haut, contenu), un script intégré avec un objet `APP` de **données fictives**, des lectures/écritures `localStorage` (`meditra.frontend.*`), et en fin de page le script d'interface commun (menu mobile, effet d'onde, apparition des blocs, comptage des indicateurs).
- `profil-test.html` est la page de **référence de la charte** (composants, couleurs, espacements, animations). `index.html` est un catalogue de démonstration : il **ne fait pas partie de l'application**.

### 6.2 Règles de conversion
1. **Inventaire d'abord** (étape 0) : pour chaque page, sections, composants, interactions, données affichées, actions.
2. **Un seul CSS** : extrais le bloc de styles commun dans `resources/css/meditra.css` (une fois, pas une copie par page) ; styles propres à une page dans un fichier séparé si nécessaire. Polices locales via `@font-face`.
3. **Layout Blade** `layouts/app.blade.php` : menu latéral + barre du haut + contenu, exactement comme les pages. Le **menu est construit depuis la configuration** selon le profil de la session (entrées, entrée active, compteur de notifications). Le sprite devient un composant `<x-icone nom="..."/>` ; les composants répétés deviennent des composants Blade anonymes (`<x-carte>`, `<x-statut>`, `<x-indicateur>`, `<x-bandeau>`, `<x-tableau>`, `<x-etat-vide>`, `<x-toast>`, `<x-dialogue>`…).
4. **Plus aucune donnée fictive** : supprime l'objet `APP`, tout `localStorage` métier et toute simulation. Les données viennent du contrôleur (relations chargées à l'avance, aucune requête dans les vues). `localStorage` n'est autorisé que pour des préférences d'affichage (try/catch). Un compte sans données voit un **état vide propre**.
5. Le **JavaScript natif** ne garde que les interactions (menu mobile, onglets, filtres côté client sur des données déjà chargées, assistant par étapes, saisie OTP, aperçu d'import, dialogues, toasts, animations). Le script d'interface commun devient `resources/js/interface.js`. Les écritures sont des **formulaires Blade** ou des `fetch` avec jeton CSRF, qui renvoient une redirection ou du JSON `{code, message, champs}`. **Ne simule jamais une réussite.**
6. Liens `*.html` → `route('...')` nommées. Déconnexion = `POST /deconnexion` avec CSRF (plus de lien vers `meditra-connexion.html`).
7. Notifications : compteur rendu par le serveur, rafraîchi toutes les 30 s par une route JSON légère, toast à l'arrivée, compteur dans le titre de l'onglet (RG-NOTIF-03).
8. Accessibilité conservée : focus, `aria-*` des champs en erreur, navigation clavier, `prefers-reduced-motion`. Messages en français à côté des champs.
9. **Captures avant / après** (ordinateur 1440 px et mobile 390 px) de chaque page convertie, issues de l'application réellement exécutée, dans `docs/captures/`.

### 6.3 Tu peux modifier le front quand il ne correspond pas aux données du back
Le front a été dessiné avant le back : certaines données, libellés ou actions ne correspondent pas au schéma ni aux règles. **Tu as l'autorisation de le modifier**, dans ces limites :

**Autorisé**
- Retirer un champ, une colonne, un indicateur ou un graphique qui n'a **pas de source** dans le schéma (sauf si une extension E1–E8 la fournit) ; ou le remplacer par la donnée réelle la plus proche, documentée.
- Ajouter les champs, colonnes, filtres et boutons qu'exigent les règles (ex. mode de dépôt, représentant, avis de l'agent, exemple d'ordre, remise partielle, bilan).
- Renommer libellés et statuts selon la section 6.1 des règles ; retirer les statuts inventés.
- Déplacer une action vers le profil qui en a la permission, retirer un bouton d'action pour un profil qui ne l'a pas.
- Réorganiser un écran quand le parcours métier l'exige (ex. assistant de dépôt physique).

**Interdit**
- Changer la charte : couleurs, polices, rayons, ombres, espacements, menu latéral, barre du haut, animations.
- Ajouter une colonne SQL, une permission ou un statut pour faire tenir un écran.
- Remplacer une donnée manquante par une valeur fictive ou calculée dans le navigateur.

Chaque modification est tracée dans la **matrice de traçabilité** (page d'origine, vue Blade, composants, routes, données réelles branchées, modifications et raison, tests).

### 6.4 Écarts déjà repérés entre le front et le back

| Front | Correction |
|---|---|
| Numéros `MDT-2026-0142` | `DIST-2026-00142` (RG-DEP-03). |
| Libellés « À traiter », « En instruction », « Transmis », « Paiement partiel », « Préparation »… | Libellés de la section 6.1 des règles + indicateurs déduits ; **pas de paiement partiel** (RG-PAY-05). |
| Statuts de cérémonie « En attente », « Préparation », « Confirmée » | `ceremonie.statut` (PROPOSEE, EN_NEGOCIATION, CONFIRMEE, TENUE, ANNULEE) et `ceremonie_proposition.statut` (EN_ATTENTE, CONFIRMEE, REFUSEE, ANNULEE). |
| « Agent instructeur », mentions d'inspecteur | Profils AGENT et CHEF_SERVICE seulement. |
| Tableaux de bord du Ministre et de la DGT avec montants et recettes | Seulement les 11 diagrammes et les compteurs `statistique_campagne` (RG-DROIT-09) `[PAR DÉFAUT]` ; le reste est retiré ou signalé. |
| Profils internes avec des champs sans colonne (fonction, téléphone…) | Afficher ce qui existe (`nom`, `prenom`, rôle, poste, e-mail) ; retirer le reste. |
| Polices Google Fonts | Hébergées localement. |
| Données `APP` + `localStorage` | Données serveur. |

Complète cette liste pendant l'inventaire.

### 6.5 Pages fournies → routes

Préfixes : `/demandeur`, `/secretariat`, `/ministre`, `/dgt`, `/dr`, `/service` (AGENT et CHEF_SERVICE : **mêmes vues**, actions affichées selon les permissions), `/regie`, `/admin`. Toutes les routes sont nommées.

| Fichier(s) | Vue / route |
|---|---|
| `meditra-connexion.html` | `/connexion`, `/inscription` (+ vérification du code), `/mot-de-passe` (oubli en 4 étapes) |
| `chargement.html` | écran de transition après connexion, puis redirection vers le tableau de bord du profil |
| `demandeur-dashboard` · `-dossiers` · `-nouveau-dossier` · `-detail-dossier` · `-ceremonies` · `-notifications` · `-profil` | `/demandeur` · `/demandeur/dossiers` · `/demandeur/dossiers/nouveau` (brouillon, import) · `/demandeur/dossiers/{dossier}` (onglets pièces, récipiendaires, compléments, liste et exemple d'ordre à confirmer, recours, paiement, remises, cérémonie, échanges, historique) · `/demandeur/ceremonies` · `/demandeur/notifications` · `/demandeur/profil` |
| `secretaire-dashboard` · `-dossiers` · `-registre` · `-notifications` · `-profil` | `/secretariat/...` (réception, contrôle documentaire, transmission au DR) |
| `dgt-*`, `ministre-*` (tableau de bord, notifications, profil) | `/dgt/...`, `/ministre/...` |
| `dr-dashboard` · `-dossiers` · `-registre` · `-notifications` · `-profil` | `/dr/...` (décision T2/T3) |
| `agent-*` et `chef-service-*` (tableau de bord, dossiers, archivage, registre, notifications, profil) + `chef-service-ordre-recette` | `/service/...` ; `/service/ordres` réservé au chef |
| `regisseur-dashboard` · `-dossiers` · `-stock` · `-registre-stock` · `-notifications` · `-profil` | `/regie/...` (quittances, remises, stock, mouvements) |

### 6.6 Pages à créer (dans la charte, à partir des composants existants)

| Profil | Pages |
|---|---|
| Public | Changement de mot de passe obligatoire ; pages d'erreur 403, 404, 419, 429, 500. La page d'accueil publique sera fournie plus tard : en attendant, `/` redirige vers `/connexion`. |
| Demandeur | Archives (RG-DEM-04) ; statistiques et finances (RG-DEM-02, dans le tableau de bord ou une page dédiée) ; dépôt de recours et de relance (dans le détail du dossier). |
| Secrétariat, agent, chef | **Dépôt physique** (assistant en 6 étapes, choix ou création d'un demandeur sans compte, RG-DEP-12/13) ; confirmation papier PAR_AGENT ; proposition de cérémonie pour un demandeur sans compte. |
| Secrétariat, Ministre, DGT, DR | Boîte des **transmissions** (reçues, prises en charge, lues). Ministre et DGT : liste des dossiers en lecture (ils ne décident ni dossier, ni recours, ni relance). |
| DR | **Recours à décider** ; **relances à décider** (le DR est le seul destinataire) ; **délégations** (éditeur versionné avec organigramme, aperçu PDF, signature) ; statistiques. |
| Service | Avis (agent) et décision (chef) par récipiendaire ; compléments (brouillon / envoi) ; notification de la liste ; **cérémonies** (propositions à confirmer ou refuser, planification, TENUE, **bilan**) ; contrôle des quittances (chef) ; retraits sans cérémonie ; stock en lecture et statistiques (chef). |
| Régisseur | Saisie de quittance dans le dossier ; **remise partielle** (payées / déjà remises / reçues / reste) ; mouvement manuel de stock ; remise d'un retrait sans cérémonie. |
| Administrateur | Tableau de bord ; campagnes et cérémonie officielle ; tarifs ; référentiels ; comptes internes (création avec mot de passe temporaire affiché une fois, désactivation) ; demandeurs (reconnaissance, rattachement d'un compte) ; cachets ; journal global ; qualité et tests ; notifications ; profil. |

Ces pages réutilisent le layout et les composants : aucun nouveau gabarit graphique.

---

## 7. Authentification

Parcours de `meditra-connexion.html`, branchés sur de vraies routes : connexion ; inscription du demandeur en 3 étapes ; vérification de l'e-mail par **code à 6 chiffres** (usage unique, 10 min, tentatives limitées, renvoi après 60 s, ancien code invalidé) ; mot de passe oublié en 4 étapes ; changement forcé au premier accès (RG-AUTH-04) ; limiteur de connexion (RG-AUTH-07) ; expiration de session ; écran `chargement.html` puis redirection selon le profil. Aucun mot de passe ni code en `localStorage`.

---

## 8. Ordre d'exécution

**Étape 0 — Audit et plan (sans code applicatif).** Dans `docs/` : (a) écarts entre règles, SQL et front ; (b) structure de dossiers ; (c) paquets et justification ; (d) inventaire du front ; (e) `CORRESPONDANCES.md` : libellés du front → mécanismes du back, matrice des transitions (état, action, profil, état d'arrivée, effets), matrice des 9 profils (pages, actions, données visibles) ; (f) matrice d'intégration (chaque donnée affichée : présente dans le SQL / calculable avec sa formule / décision métier / après une action réelle / démonstration à retirer) ; (g) hypothèses retenues.

**Étape 1 — Fondations de données.** Projet Laravel, Git, `.env` / `.env.testing`, bases `meditra` et `meditra_test`, migrations v4 + V1–V10 + E1–E8, déclencheurs, vues, seeders, modèles, enums. Tests : rapport de différences, déclencheurs, CHECK, uniques générées, idempotence des seeders.

**Étape 2 — Authentification, profils et permissions.** Sessions, parcours de connexion et d'inscription, codes, `config/permissions.php`, policies, étendue de visibilité, comptes internes (création, désactivation, dernier administrateur). Tests : chaque ligne de la matrice, isolation des données, accès par URL et identifiant modifié.

**Étape 3 — Socle visuel.** CSS unique, polices locales, layout, menus par profil, composants, connexion, chargement, pages d'erreur, `profil-test` reproduit en Blade comme page de contrôle (environnement local). Tests de navigateur et captures avant/après.

**Étape 4 — Dépôt.** En ligne (brouillon, import, assistant) et physique (demandeur sans compte, reçu), représentant figé, CNI masquée, profil du demandeur. Pages demandeur et dépôt physique.

**Étape 5 — Circuit de décision et instruction.** Transmissions, décisions du DR, recours, avis de l'agent, décision du chef, compléments, éligibilité, anti-doublon, T6 avec exemple d'ordre et PDF, T7 (en ligne et PAR_AGENT), rappel. Pages secrétariat, Ministre, DGT, DR, Service.

**Étape 6 — Documents et signature.** Stockage privé, téléchargement contrôlé, courriers générés, signature par code, visas, cachets, scellement, journal chaîné et commande de vérification, PDF.

**Étape 7 — Paiement, remise et stock.** T9 (chef, montant conforme), quittance (dépôt ou saisie), contrôle avec séparation des tâches, T10, remise partielle, T11, mouvements manuels, retrait sans cérémonie, alertes. Pages chef (ordres) et régisseur.

**Étape 8 — Cérémonies, archivage, administration, statistiques.** Propositions, confirmation, planification, TENUE, délégation du DR, bilan, T12b, T13, Archives, relances et rattrapage ; espace administrateur complet ; statistiques globales et du demandeur ; compteurs et `campagne:snapshot` ; notifications de tous les événements ; messagerie ; qualité et tests.

**Étape 9 — Durcissement.** Parcours de bout en bout (section 10), N+1 et index, revue des routes et téléchargements, en-têtes de sécurité, limiteurs, sauvegarde documentée, README, `.env.example`, guide de déploiement. Relance de **toute** la suite, Pint et Larastan.

---

## 9. Conventions

- PSR-12, `declare(strict_types=1)`. Noms **français pour le métier** (`Dossier`, `ConfirmerListe`, `EnregistrerRemise`), anglais pour le technique (`Controller`, `Request`, `Policy`).
- Un FormRequest par formulaire, une policy par modèle sensible, une ressource par réponse JSON. Aucune requête dans les vues.
- Transactions pour toute écriture sur plusieurs tables ; `lockForUpdate()` sur le stock et les séquences de numéros.
- Commandes Artisan : `meditra:admin`, `meditra:journal-verifier`, `campagne:snapshot`, `qualite:purger`.

---

## 10. Tests

- **Composer** : `composer test` lance tout (Pest sur `meditra_test`, puis tests de navigateur).
- **Par règle** : cas nominal, refus par profil (403 / 404), état incompatible (409), validation (422), nom du test = ID de la règle.
- **Base de données** : les 8 déclencheurs, les CHECK, les uniques générées, les 14 vues sur un jeu de données connu, l'équivalence du schéma.
- **Bout en bout** (obligatoires) :
  1. Dépôt en ligne → T2 → T4 → avis de l'agent → décisions du chef → T6 (exemple d'ordre 1 Or + 1 Bronze = **39 000**, inchangé après changement de tarif) → T7 en ligne → T9 → quittance déposée et contrôlée → T10 → remise partielle (2 Argent + 1 Bronze ; 1 Argent puis le reste) → T11 → proposition de cérémonie confirmée → T12a → TENUE → bilan avec un non décoré (T12b refusée) → rattrapage → nouveau bilan → T12b → T13 → dossier en lecture seule, diplômes téléchargeables.
  2. Dépôt **physique** par le secrétariat pour un demandeur **sans compte** → aucune notification au demandeur, e-mail si `email_contact` → confirmation PAR_AGENT sans scan (422) puis avec scan → quittance **saisie par le régisseur** et contrôlée par le chef.
  3. Agent : valider, refuser, envoyer un complément, notifier, émettre, confirmer une cérémonie, archiver → 403 ; chef : succès.
  4. Rejet du DR → recours → acceptation → T5 ; liste notifiée → recours → T8 → nouvelle T6 au tarif du jour ; relance après cérémonie : destinataire toujours DR, décidée par le DR seul (Ministre, DGT → 403).
  5. Anti-doublon : même CNI, même demandeur, même métal → T7 refusée, aucune médaille ; autre demandeur → accepté.
  6. Stock à 0 : remise refusée, rien d'écrit ; sortie manuelle au-delà du stock : 409.
  7. Délégation : DR crée v1 puis v2 ; chef, agent, Ministre → 403 ; version scellée non modifiable.
  8. Isolation : un demandeur ne voit rien d'un autre (dossiers, fichiers, statistiques, cérémonies, messages) ; l'administrateur ne voit aucun dossier.
- **Navigateur** : chaque page convertie s'affiche pour son profil, est refusée aux autres, et ses actions principales fonctionnent ; captures 1440 px et 390 px.

---

## 11. Valeurs par défaut

Les questions métier ouvertes et leurs valeurs par défaut sont dans la **section 26 des règles** : applique-les, consigne-les, liste-les dans le rapport final. Valeurs techniques :

1. Devise FCFA, séparateur de milliers « espace insécable », pas de décimales à l'affichage.
2. Pas d'espace « récipiendaire » : un récipiendaire n'a pas de compte.
3. La page d'accueil publique sera fournie plus tard (`/` → `/connexion`).
4. Le catalogue `index.html` n'est pas livré (éventuellement une route de développement en `local`).
5. E-mails en `log` en local ; aucune adresse réelle dans les seeders (`example.test`).

---

## 12. Rapport final

Un seul rapport, à la fin de l'étape 9, dans `docs/RAPPORT_FINAL.md`, et son résumé en réponse :

1. **État de chaque fonctionnalité** (états de la section 13).
2. **Hypothèses à valider** : numérotées, règle appliquée, emplacement dans le code ou la configuration, ce que je dois confirmer.
3. **Choix et raisons** (renvoi à `docs/DECISIONS.md`).
4. **Écarts** par rapport aux règles, au SQL et au front, avec le rapport de différences du schéma et la liste des modifications du front.
5. **Tests** : pour chaque vérification, la commande exacte et son **résultat réel collé** ; résultats de `composer test`, Pint et Larastan.
6. **Comment vérifier** : commandes, URL, comptes de démonstration (`local` / `testing`).
7. **Ce qui reste** : bloqué, partiel ou en échec, avec la cause.

Annexes : matrice de traçabilité du front, matrices de `CORRESPONDANCES.md`, matrice d'intégration, matrice des permissions générée depuis `config/permissions.php`, contrat des routes JSON (route, méthode, permission, entrée, sortie, erreurs).

---

## 13. Critères de validation

Pour chaque fonctionnalité, **un seul** état : **Implémentée et testée** · **Implémentée, test en échec** · **Partiellement implémentée** · **Interface uniquement** · **Bloquée** · **Non commencée**.

Une route, un contrôleur, un bouton ou une vue ne prouvent jamais une fonctionnalité. Pour chaque page métier, vérifie : accès autorisé et refusé ; données réelles ; validations serveur ; autorisation sur **chaque objet** ; états chargement / succès / erreur / vide ; persistance ; effets de bord (historique, notifications, journal, fichiers, stock) ; non-régression visuelle.

Les captures viennent de l'application réellement exécutée (URL, environnement, profil indiqués). Aucun résultat de test n'est inventé ; aucune fonctionnalité n'est remplacée par une simulation, un faux bouton, une réponse codée en dur ou des données fictives.

---

Commence par l'**étape 0**, puis enchaîne jusqu'à l'étape 9 sans t'arrêter. Le seul message attendu est le **rapport final**.
