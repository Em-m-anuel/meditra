# MÉDITRA — Règles complètes du back-end

**Version 2.0 — 26 octobre 2026.** Remplace la v1.0 du 24 octobre et intègre toutes les décisions de la refonte v5 (suppression du poste INSPECTEUR, dépôt physique, l'agent prépare et le chef décide, confirmation unique, délégation par le DR, remise partielle, bilan de cérémonie, archivage, espace demandeur).

**Schéma de référence** : `distinctions_nationales_v4.sql` **puis** `migration_v5_depuis_v4.sql`, appliqués dans cet ordre (52 tables, 14 vues, 8 déclencheurs). Les extensions de schéma autorisées sont listées en **section 24**.

Ce document est **l'autorité métier**. Le prompt de l'agent décrit la méthode de travail ; en cas de conflit sur une règle métier, **ce document prévaut**.

---

## 0. Mode d'emploi

Chaque règle a un **ID stable** (`RG-ELIG-03`), un **énoncé**, un **code d'erreur** stable (les tests vérifient le code, jamais le texte) et un **test attendu**.

| Statut | Sens |
|---|---|
| `[VALIDÉ]` | Confirmé par Nyx_. |
| `[PROPOSÉ]` | Proposition, appliquée par défaut tant qu'elle n'est pas corrigée. |
| `[PAR DÉFAUT]` | Question encore ouverte : la valeur indiquée s'applique (liste en section 26). |

**Règle de livraison** : le nom de chaque test contient l'ID de la règle (ex. `it('RG-ELIG-03 …')`). Une règle sans test est une règle non vérifiée.

### Ce qui a changé depuis la v1.0

| v1.0 | v2.0 |
|---|---|
| Trois postes du Service : AGENT, INSPECTEUR, CHEF_SERVICE | **INSPECTEUR supprimé.** Postes : AGENT et CHEF_SERVICE. **L'agent prépare, le chef décide.** |
| L'inspecteur ou le chef valide les récipiendaires, notifie la liste, émet l'ordre | **Le chef seul** décide des récipiendaires, envoie les compléments, notifie la liste et émet l'ordre ; l'agent donne un **avis** et rédige des **brouillons** de complément. |
| Dépôt par le demandeur (ou saisie déléguée) | Deux modes : **EN_LIGNE** (demandeur) et **PHYSIQUE** (secrétariat, agent ou chef), y compris pour un **demandeur sans compte**. |
| Acceptation de la liste par le demandeur | **Confirmation unique** de la liste **et d'un exemple d'ordre de recette** (montant figé à la notification). Confirmation papier possible (PAR_AGENT, scan obligatoire). |
| Délégation rédigée par l'agent ou le chef | **Rédigée, modifiée et signée par le DR seul**, versionnée, une par (cérémonie, demandeur). |
| Remise : toutes les médailles d'un coup ou partielle sans détail | **Remise partielle détaillée** par métal : payées / déjà remises / reçues / reste (`remise_ligne`). Le régisseur saisit aussi les entrées/sorties manuelles de stock et peut saisir la quittance. |
| Clôture : présence enregistrée pour chaque récipiendaire | **Bilan de cérémonie** : « tous décorés » ou liste des non décorés avec motif. Le dossier reste ouvert tant qu'un récipiendaire n'est pas décoré. |
| Contre-proposition de cérémonie par le chef | **Pas de contre-proposition** : le chef confirme ou refuse ; le demandeur refait une proposition. |
| Statut final CLOTURE | Nouveau statut **ARCHIVE** (chef seul, irréversible, lecture seule). |
| Navigation horizontale ; cloche flottante sous la barre du haut | Interface du **profil test** : menu latéral + barre du haut avec cloche et compteur (RG-NOTIF-03). |
| Trois niveaux de secrétariat envisagés ; relance adressée au DR, à la DGT ou au Ministre | **Un seul profil SECRETARIAT** ; **aucun choix de destinataire** : dossiers, recours et relances passent tous par le DR. |

---

## 1. Architecture (RG-ARCH)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-ARCH-01 `[VALIDÉ]` | Flux unique **Route → Controller → FormRequest → Action → Modèles**. Le contrôleur ne contient que du HTTP ; le FormRequest valide la *forme*. | — | Test d'architecture : aucun contrôleur n'appelle `DB::`. |
| RG-ARCH-02 `[VALIDÉ]` | **Une Action = un cas d'usage**, une seule méthode publique `execute()`. Toute règle métier vit dans l'Action ou un service de domaine. | — | Chaque Action testée isolément. |
| RG-ARCH-03 `[VALIDÉ]` | Toute Action qui écrit dans plusieurs tables s'exécute dans `DB::transaction()`. Le stock se modifie avec `lockForUpdate()`. | — | Échec au milieu : rien n'est écrit. |
| RG-ARCH-04 `[VALIDÉ]` | Chaque ENUM SQL = un **Enum PHP** typé (`DossierStatut`, `RoleInterne`, `PosteService`, `Metal`, `ModeDepot`, `OrigineCreation`, `ConfirmationMode`, `StatutComplement`, `MotifMouvement`, `StatutProposition`, `StatutBrouillon`…). Aucune chaîne en dur. | — | Test d'architecture. |
| RG-ARCH-05 `[VALIDÉ]` | Une violation lève `RegleMetierException` avec **code stable** et statut HTTP : 422 donnée invalide, 403 interdit, 404 introuvable, 409 état incompatible. Réponse JSON unique `{ "code": "...", "message": "...", "champs": {...} }` ; en rendu Blade, le message s'affiche à côté du champ ou dans un toast. | — | Le front s'appuie sur `code`. |
| RG-ARCH-06 `[VALIDÉ]` | Triggers et CHECK SQL = **filet de sécurité**. L'Action vérifie d'abord ; si la base refuse malgré tout, l'erreur devient 409 `*_VIOLATION_BASE` et une anomalie est journalisée. Jamais de `SQLSTATE 45000` brut vers le front. | 409 `*_VIOLATION_BASE` | Insertion directe d'un doublon → 409. |
| RG-ARCH-07 `[VALIDÉ]` | **Aucune suppression physique** de donnée métier ; on change un statut ou on désactive. FK en `RESTRICT`. Journaux jamais purgés (sauf tables de diagnostic qualité, RG-QUAL-05). | — | Aucun `delete()` sur un modèle métier. |
| RG-ARCH-08 `[VALIDÉ]` | Migrations Laravel reconstruisant **exactement** le SQL v4 puis la migration v5 (noms de tables et colonnes inchangés). Les extensions (section 24) sont des migrations **additives** séparées : jamais d'ENUM renommé ni de FK existante modifiée, sauf l'exception E3 si elle est retenue. Authentification sur `utilisateur`. | — | Schéma reconstruit = référence + extensions. |
| RG-ARCH-09 `[VALIDÉ]` | Seuils d'ancienneté, tarifs, dates par défaut de campagne, réglages (`exiger_demandeur_reconnu`, durée de session, taille des pièces, seuil de stock…) lus depuis `config/distinctions.php` ou la table `tarif`, jamais en dur. | — | Changer un tarif change le prochain exemple d'ordre. |
| RG-ARCH-10 `[VALIDÉ]` | Tests sur **MySQL 8** (pas SQLite), sur une **base dédiée** (suffixe `_test`). Un test refuse de tourner si la base est celle de l'application. | `ARCH_BASE_APPLICATION` | Lancer les tests sur la base applicative : refus. |
| RG-ARCH-11 `[VALIDÉ]` | **Ne jamais compter sur la valeur par défaut d'un ENUM obligatoire.** `sexe`, `role`, `type_demandeur`, `metal`, `origine`, `mode_depot`, `origine_creation`, `statut` des nouvelles tables, `mode_saisie`, `motif_type` sont toujours renseignés explicitement et `required` dans le FormRequest. | 422 `VALIDATION` | Requête sans `sexe` → 422, jamais « M ». |
| RG-ARCH-12 `[VALIDÉ]` | **Le profil vient du serveur**, jamais du navigateur : rôle, poste et permissions sont lus de la session. Aucune bascule de profil en production. | 403 | Forcer un profil par URL, stockage ou requête : sans effet. |
| RG-ARCH-13 `[VALIDÉ]` | **Un seul composant (`DossierWorkflow`) écrit `dossier.statut`**, et il écrit `historique_dossier` dans la même transaction. | — | Test d'architecture. |
| RG-ARCH-14 `[PROPOSÉ]` | Opérations rejouables (dépôt, confirmation, paiement, remise, mouvement de stock) : **clé d'idempotence** ; un double clic ne crée pas deux lignes. | 409 `ARCH_DOUBLE_ENVOI` | Deux POST identiques → un seul enregistrement. |
| RG-ARCH-15 `[PROPOSÉ]` | Pagination bornée (max 100) sur toute liste ; pas de `Model::all()` global ; pas de N+1. | — | Assertion sur le nombre de requêtes. |
| RG-ARCH-16 `[VALIDÉ]` | **Aucune donnée inventée.** Un manque s'affiche « indisponible » ou par un état vide, jamais par une valeur fictive. Les données de démonstration n'existent qu'en `local` et `testing`. | — | En production, aucun seeder de démonstration. |

---

## 2. Authentification et comptes (RG-AUTH)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-AUTH-01 `[VALIDÉ]` | **Inscription publique réservée au demandeur** (entreprise ou ministère). Les comptes internes sont créés par l'ADMINISTRATEUR. | 403 | Inscription avec un rôle interne : refusée. |
| RG-AUTH-02 `[VALIDÉ]` | Le login est l'**adresse e-mail** (`utilisateur.login`), unique. L'inscription envoie un **code à 6 chiffres** pour vérifier l'adresse (extension E1 `email_verified_at`, codes en E2). Tant qu'elle n'est pas vérifiée, aucun dépôt. Codes : usage unique, expiration 10 min (configurable), tentatives limitées, renvoi possible, l'ancien code est invalidé. | 403 `AUTH_EMAIL_NON_VERIFIE` | Dépôt avec e-mail non vérifié : 403. Code expiré, réutilisé ou 6e essai : refusé. |
| RG-AUTH-03 `[VALIDÉ]` | Mot de passe **haché** (`mot_de_passe_hash`) ; jamais stocké ni journalisé en clair. Réinitialisation par code à durée limitée (parcours en 4 étapes de la page de connexion). | — | Aucune colonne ne contient un mot de passe en clair. |
| RG-AUTH-04 `[VALIDÉ]` | **Création d'un compte interne** : `utilisateur` + `compte_interne` + journal dans **une transaction**. Mot de passe temporaire généré, haché, affiché **une seule fois** à l'administrateur (`Cache-Control: no-store`), jamais journalisé ; **changement forcé** à la première connexion (`doit_changer_mot_de_passe`). | 422 | Échec du profil : aucun `utilisateur` créé. |
| RG-AUTH-05 `[VALIDÉ]` | **Poste du Service** (`poste_service` ∈ AGENT, CHEF_SERVICE) obligatoire si `role = SERVICE_DISTINCTIONS`, interdit sinon (CHECK `ck_ci_poste`). La valeur INSPECTEUR n'existe plus nulle part (code, config, seeders, libellés, tests). | 422 `AUTH_POSTE_INCOHERENT` | MINISTRE avec un poste : 422 ; création avec INSPECTEUR : 422. |
| RG-AUTH-06 `[VALIDÉ]` | **Désactivation sans suppression** (`est_actif = 0`, date, auteur) ; elle **invalide les sessions** de la personne. Un administrateur ne peut pas se désactiver lui-même ; **le dernier administrateur actif ne peut pas être désactivé**. Un administrateur peut en créer un autre. | 409 `AUTH_DERNIER_ADMIN` / `AUTH_AUTO_DESACTIVATION` | Désactiver le seul admin : 409. |
| RG-AUTH-07 `[PROPOSÉ]` | Limitation des tentatives de connexion (5 essais puis délai), en-têtes anti-cache sur les pages authentifiées, expiration de session après inactivité (configuration, 30 min proposé). | 429 `AUTH_TROP_DE_TENTATIVES` | 6 échecs → 429. |
| RG-AUTH-08 `[VALIDÉ]` | **Un demandeur ne voit que ses propres données** ; un compte interne ne voit que ce que son rôle autorise (RG-DROIT). | 403 / 404 | Demandeur A lit le dossier de B : 404. |
| RG-AUTH-09 `[VALIDÉ]` | Un compte désactivé ne peut plus se connecter ; un compte avec `doit_changer_mot_de_passe = 1` n'accède qu'à la page de changement de mot de passe. | 403 | Connexion d'un compte désactivé : refusée. |
| RG-AUTH-10 `[VALIDÉ]` | **Rattacher un compte** à un demandeur créé par saisie interne (`utilisateur_id` renseigné plus tard) : ADMINISTRATEUR ou SECRETARIAT, sans changer `origine_creation` ; journalisé. | 409 si le demandeur a déjà un compte | — |

---

## 3. Droits par profil (RG-DROIT)

### 3.1 Principe
Toute action est protégée par **une permission** (`config/permissions.php`) vérifiée par une policy **côté serveur**. Le front masque ce qui est interdit mais **n'est jamais l'autorité**. Aucune permission n'est ajoutée ou élargie sans décision explicite.

**Profils** (9) : DEMANDEUR (type ENTREPRISE ou MINISTERE, même circuit), SECRETARIAT, MINISTRE, DGT, DR, AGENT et CHEF_SERVICE (rôle `SERVICE_DISTINCTIONS`), REGISSEUR, ADMINISTRATEUR.

### 3.2 Matrice des permissions `[VALIDÉ]`

| Permission | Profils |
|---|---|
| `dossier.voir` | tous sauf ADMINISTRATEUR (étendue : RG-DROIT-05) |
| `dossier.creer_en_ligne` | DEMANDEUR |
| `dossier.creer_physique` | SECRETARIAT, AGENT, CHEF_SERVICE |
| `demandeur.creer_sans_compte` | SECRETARIAT, AGENT, CHEF_SERVICE |
| `dossier.transmettre` | SECRETARIAT, MINISTRE, DGT, DR |
| `dossier.decider` (T2, T3) | DR |
| `dossier.instruire` (T4, vérifications, localisation physique) | AGENT, CHEF_SERVICE |
| `recipiendaire.avis` (FAVORABLE / DEFAVORABLE + motif) | AGENT, CHEF_SERVICE |
| `recipiendaire.decider` (valider / refuser) | **CHEF_SERVICE** |
| `complement.rediger` (BROUILLON) | AGENT, CHEF_SERVICE |
| `complement.envoyer` | **CHEF_SERVICE** |
| `complement.repondre` | DEMANDEUR |
| `liste.notifier` (T6) | **CHEF_SERVICE** |
| `liste.confirmer` (T7 en ligne) | DEMANDEUR |
| `liste.confirmer_pour` (T7 PAR_AGENT) | SECRETARIAT, AGENT, CHEF_SERVICE |
| `liste.rappeler` (rappel, sans changement de statut) | CHEF_SERVICE |
| `ordre.emettre` (T9) | **CHEF_SERVICE** |
| `quittance.deposer` | DEMANDEUR |
| `quittance.saisir` (au nom du demandeur) | REGISSEUR |
| `paiement.decider` (approuver / refuser une quittance, T10) | REGISSEUR, CHEF_SERVICE (séparation des tâches : RG-PAY-13) |
| `recours.deposer` | DEMANDEUR |
| `recours.voir` | DR, AGENT, CHEF_SERVICE, DEMANDEUR (les siens) |
| `recours.decider` | **DR seul** |
| `relance.deposer` | DEMANDEUR |
| `relance.decider` | **DR seul** |
| `delegation.rediger` (créer / modifier / signer) | **DR seul** |
| `delegation.voir` | DR, MINISTRE, DGT, AGENT, CHEF_SERVICE, DEMANDEUR (la sienne) |
| `ceremonie.proposer` | DEMANDEUR |
| `ceremonie.proposer_pour` | SECRETARIAT, AGENT, CHEF_SERVICE |
| `ceremonie.confirmer` (confirmer / refuser une proposition ; planifier ; date, lieu ; marquer TENUE) | CHEF_SERVICE |
| `ceremonie.voir` | profils internes sauf ADMINISTRATEUR (calendrier) ; DEMANDEUR (les siennes) |
| `bilan.saisir` | AGENT, CHEF_SERVICE |
| `dossier.archiver` (T13) | CHEF_SERVICE |
| `remise.enregistrer` | REGISSEUR |
| `retrait.valider` / `retrait.remettre` | CHEF_SERVICE / REGISSEUR |
| `stock.voir` | REGISSEUR, CHEF_SERVICE |
| `stock.saisir` (entrées / sorties manuelles) | REGISSEUR |
| `diplome.voir` | DEMANDEUR (les siens), AGENT, CHEF_SERVICE, REGISSEUR |
| `document.voir` | tous sauf ADMINISTRATEUR, selon l'accès au dossier |
| `message.ecrire` | AGENT, CHEF_SERVICE, DEMANDEUR propriétaire (RG-MSG) |
| `statistiques.voir` (11 diagrammes globaux) | MINISTRE, DGT, DR, CHEF_SERVICE |
| `demandeur.statistiques` (ses propres chiffres) | DEMANDEUR |
| `demandeur.reconnaitre`, `admin.*` (campagnes, tarifs, référentiels, comptes, cachets, cérémonie officielle, qualité, journal global) | ADMINISTRATEUR |
| `notification.voir` | tous (les siennes) |

### 3.3 Matrice du Service `[VALIDÉ]`

| Fonction | AGENT | CHEF_SERVICE |
|---|---|---|
| Voir les dossiers | oui | oui |
| Saisir un dossier physique / créer un demandeur sans compte | oui | oui |
| Prise en charge (T4), vérifications, localisation physique | oui | oui |
| Avis sur un récipiendaire | oui | oui |
| Valider / refuser un récipiendaire | **non** | oui |
| Rédiger un complément (brouillon) | oui | oui |
| Envoyer un complément | **non** | oui |
| Lire les recours | oui | oui |
| Notifier la liste (T6), rappeler, émettre l'ordre (T9) | **non** | oui |
| Enregistrer une confirmation papier (PAR_AGENT) | oui | oui |
| Confirmer / refuser une proposition de cérémonie, planifier, marquer TENUE | **non** | oui |
| Saisir le bilan de cérémonie | oui | oui |
| Archiver (T13) | **non** | oui |
| Contrôler une quittance, valider un retrait sans cérémonie | **non** | oui |
| Stock (lecture), statistiques, supervision | **non** | oui |
| Rédiger la délégation | **non** | **non** (DR seul) |
| Décider d'un recours | **non** | **non** (DR seul) |

### 3.4 Règles

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-DROIT-01 `[VALIDÉ]` | Toute action vérifie sa permission **côté serveur**. | 403 `DROIT_INTERDIT` | Un profil non autorisé appelant la route : 403. |
| RG-DROIT-02 `[VALIDÉ]` | **Agent prépare, chef décide** : un AGENT qui valide, refuse, envoie un complément, notifie, émet l'ordre, confirme une cérémonie ou archive reçoit 403. | 403 `INS_DECISION_CHEF_SEUL` | Chaque action refusée à l'agent, réussie pour le chef. |
| RG-DROIT-03 `[VALIDÉ]` | Le **Ministre et la DGT transmettent, ne décident pas** : seul le DR approuve ou rejette. | 403 `ETAT_ACTEUR_NON_AUTORISE` | Ministre approuve : 403. |
| RG-DROIT-04 `[VALIDÉ]` | Le CHEF ne remplace jamais le DR pour décider d'un recours ni pour rédiger la délégation. | 403 `ECH_RECOURS_DR_SEUL` / `DEL_DR_SEUL` | — |
| RG-DROIT-05 `[VALIDÉ]` | **Étendue de visibilité** : DEMANDEUR = ses dossiers ; SECRETARIAT, MINISTRE, DGT, DR, AGENT, CHEF_SERVICE = tous les dossiers de la campagne affichée (lecture, sauf actions permises) ; REGISSEUR = dossiers concernés par le paiement, la remise ou le stock (statut ORDRE_EMIS et suivants) `[PAR DÉFAUT]` ; ADMINISTRATEUR = aucun dossier. | 403 / 404 | Admin liste les dossiers : 403 ; régisseur ouvre un dossier EN_ETUDE : 404. |
| RG-DROIT-06 `[VALIDÉ]` | **Localisation physique** : visible côté Ministère seulement, jamais au demandeur. | — | Réponse demandeur sans `localisation_physique`. |
| RG-DROIT-07 `[VALIDÉ]` | Cérémonies : calendrier visible des profils internes ; le demandeur ne voit que les siennes (RG-CER-12). Journal : chacun ses propres événements ; journal global pour l'ADMINISTRATEUR. Stock : REGISSEUR et CHEF. | 403 / 404 | — |
| RG-DROIT-08 `[VALIDÉ]` | Achats, fournisseurs, budgets : **« indisponible »** tant que la chaîne n'est pas validée avec le régisseur ; jamais de donnée fictive. | — | — |
| RG-DROIT-09 `[VALIDÉ]` | **Statistiques** : les 11 diagrammes sont visibles de MINISTRE, DGT, DR et CHEF_SERVICE ; le délai de traitement est un résumé pour Ministre et DGT, un graphique complet pour DR et CHEF. Le DEMANDEUR n'a que ses propres chiffres (RG-DEM-02). L'ADMINISTRATEUR n'a que les diagrammes de qualité. Autres profils : refusés. | 403 | Demandeur sur un diagramme global : 403. |
| RG-DROIT-10 `[VALIDÉ]` | Un dossier **ARCHIVE** est en lecture seule pour tous (RG-ARC-01). | 409 `ARC_DOSSIER_ARCHIVE_LECTURE_SEULE` | Toute écriture : 409. |

---

## 4. Campagne (RG-CAMP)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-CAMP-01 `[VALIDÉ]` | **Une campagne par année** (`annee` unique). | 422 `CAMP_ANNEE_EXISTANTE` | Créer 2026 deux fois : 422. |
| RG-CAMP-02 `[VALIDÉ]` | Dépôt du **10 janvier au 31 mars** (valeurs par défaut) ; `date_debut_depot ≤ date_fin_depot`. | 422 `CAMP_DATES_INCOHERENTES` | Fin avant début : 422. |
| RG-CAMP-03 `[VALIDÉ]` | **Seule la date limite de dépôt est prorogeable**. La prorogation ne touche pas la cérémonie. | 422 | Modifier le début après ouverture : refusé. |
| RG-CAMP-04 `[VALIDÉ]` | Cérémonie officielle : **1er mai par défaut, date et lieu modifiables** chaque année. | — | Changer la date : acceptée. |
| RG-CAMP-05 `[VALIDÉ]` | **Pas de suppression** de campagne. Édition **bloquée** si un dossier est CLOTURE ou ARCHIVE. Seul l'ADMINISTRATEUR modifie ; action journalisée. | 409 `CAMP_VERROUILLEE` | Éditer une campagne avec dossier clôturé : 409. |
| RG-CAMP-06 `[VALIDÉ]` | Les statistiques et l'ancienneté se rattachent à l'**année de la campagne**, pas à la date de dépôt. | — | — |
| RG-CAMP-07 `[PROPOSÉ]` | La **campagne affichée** par défaut est celle de l'année en cours ; un sélecteur permet de consulter les précédentes. | — | — |

---

## 5. Dépôt d'un dossier et demandeur (RG-DEP)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-DEP-01 `[VALIDÉ]` | La règle « seul un demandeur **reconnu** peut déposer » est **suspendue** : réglage `distinctions.exiger_demandeur_reconnu`, **défaut `false`**. Si `true` : demandeur non reconnu refusé (en ligne et physique). La colonne `est_reconnu` reste affichée. Seul l'ADMINISTRATEUR reconnaît un demandeur. | 403 `DEP_DEMANDEUR_NON_RECONNU` | Testé dans les deux états du réglage. |
| RG-DEP-02 `[VALIDÉ]` | Le dépôt exige un **courrier d'initiation** (`document.type = COURRIER_INITIATION`) et **au moins un récipiendaire** ; dossier, pièces, récipiendaires et métaux créés dans **une seule transaction**. La liste des récipiendaires est **générée par l'application**, pas téléversée. | 422 `DEP_PIECES_MANQUANTES` | Sans courrier : 422, rien en base. |
| RG-DEP-03 `[VALIDÉ]` | `numero` généré : `DIST-{année}-{séquence 5 chiffres}` (ex. `DIST-2026-00142`), unique, sans trou de concurrence. | — | Deux dépôts simultanés : deux numéros distincts. |
| RG-DEP-04 `[VALIDÉ]` | À la création : `statut = SOUMIS` ; **`destinataire_initial` = DR**, figé. | — | Le dossier arrive chez le DR. |
| RG-DEP-05 `[PAR DÉFAUT]` | **Dépôt après `date_fin_depot`** (en ligne ou physique) : accepté et qualifié « hors délai » (qualité calculée, pas de colonne) ; ses distinctions sont remises en cérémonie HORS_DELAI. | — | Dépôt le 15 avril : accepté, `estHorsDelai() = true`. |
| RG-DEP-06 `[VALIDÉ]` | Chaque récipiendaire porte **1 à 3 métaux** demandés (`distinction_demandee`). | 422 `DEP_METAL_REQUIS` | 0 ou 4 métaux : 422. |
| RG-DEP-07 `[VALIDÉ]` | `sexe` et `nationalite_id` **obligatoires** pour chaque récipiendaire. | 422 `DEP_CHAMP_STATISTIQUE_REQUIS` | Sans sexe : 422. |
| RG-DEP-08 `[VALIDÉ]` | `annee_entree_service` : entier à 4 chiffres, ≤ année de la campagne. | 422 `DEP_ANNEE_ENTREE_INVALIDE` | 2027 pour campagne 2026 : 422. |
| RG-DEP-09 `[VALIDÉ]` | `saisi_par_id` mémorise le compte interne qui a saisi un dossier physique ; vide = déposé en ligne par le demandeur. | — | — |
| RG-DEP-10 `[PROPOSÉ]` | Pièces : formats pdf, jpg, png ; taille maximale en configuration (10 Mo proposé) ; vérification du type réel ; nom stocké aléatoire. | 422 `DEP_PIECE_INVALIDE` | Fichier .exe : 422. |
| RG-DEP-11 `[PROPOSÉ]` | Tant que le dossier est SOUMIS, le demandeur (ou le compte qui a saisi le dossier physique) peut compléter ou corriger ses récipiendaires ; ensuite seules les réponses aux compléments sont possibles. | 409 `DEP_DOSSIER_VERROUILLE` | Modifier après APPROUVE : 409. |
| RG-DEP-12 `[VALIDÉ]` | **Mode de dépôt** : un dossier du demandeur a `mode_depot = EN_LIGNE` ; un dossier saisi par un compte interne a `mode_depot = PHYSIQUE`, `saisi_par_id`, `date_depot_physique` (date du reçu, ≤ aujourd'hui) et, si disponible, `reference_recepisse`. Aucune valeur par défaut. | 422 `DEP_MODE_DEPOT_REQUIS` | Dépôt physique sans date de reçu : 422. |
| RG-DEP-13 `[VALIDÉ]` | **Demandeur sans compte** : le secrétariat, l'agent ou le chef peut créer le demandeur (`origine_creation = SAISIE_INTERNE`, `cree_par_id`, `utilisateur_id = NULL`) avec les mêmes champs obligatoires qu'à l'inscription (nom, type, province ; secteur si entreprise), représentant obligatoire, `email_contact` ou téléphone recommandé. Recherche anti-doublon sur nom + NIF avant création, contournable avec confirmation explicite. | 409 `DEP_DEMANDEUR_PROBABLE_DOUBLON` | Même nom + NIF : 409, puis création acceptée avec confirmation. |
| RG-DEP-14 `[VALIDÉ]` | Pièces papier numérisées par un compte interne : `origine = TELEVERSE`, `date_scan` renseignée ; mêmes contrôles que RG-DEP-10. | 422 | — |
| RG-DEP-15 `[VALIDÉ]` | **Demandeur sans compte** : aucune notification interne pour lui ; si `email_contact` existe, e-mail ; sinon la notification est créée pour le personnel concerné avec la mention « à informer par courrier ». Son suivi se fait par le Service. | — | Dépôt physique sans compte : aucune notification au demandeur ; e-mail si `email_contact`. |
| RG-DEP-16 `[VALIDÉ]` | Le **représentant** (nom, prénom, fonction, téléphone, e-mail) est saisi dans `demandeur` et **copié, figé**, dans `dossier` au dépôt. Un changement ultérieur du profil ne modifie jamais un dossier existant. | — | Modifier le représentant : les dossiers existants gardent l'ancien. |
| RG-DEP-17 `[VALIDÉ]` | **Brouillon** serveur (`brouillon_dossier`) : un seul `ACTIF` par (demandeur, campagne) ; `donnees` JSON validé en forme seulement ; n'écrit rien dans `dossier`. À la soumission réussie → `CONVERTI` + `dossier_id`. Les comptes internes n'utilisent pas de brouillon serveur. | 409 `DEP_BROUILLON_DEJA_ACTIF` | Deuxième brouillon actif : 409. |
| RG-DEP-18 `[VALIDÉ]` | **Import CSV / XLSX** de la liste des récipiendaires : la prévisualisation renvoie, par ligne, `valide` ou la liste d'erreurs (CNI en double, année invalide, sexe manquant, nationalité inconnue, taux hors 0-100, métaux non reconnus ; taux sans justificatif = avertissement) **sans rien écrire** ; le dépôt **revalide tout**. Colonnes : `nom, prenom, cni, poste, annee_entree_service, sexe, nationalite, date_deces, taux_mutilation, metaux`. UTF-8, taille et nombre de lignes bornés (configuration), fichier non conservé. | 422 `DEP_IMPORT_INVALIDE` | Fichier mixte : aperçu correct, aucune écriture. |
| RG-DEP-19 `[PROPOSÉ]` | Le formulaire de dépôt (en ligne et physique) suit l'assistant en 6 étapes du front (Demandeur, Informations, Récipiendaires, Documents, Récapitulatif, Confirmation). | — | — |

---

## 6. Machine à états du dossier (RG-ETAT)

**Principe** : `DossierWorkflow` seul change `dossier.statut` ; chaque transition vérifie acteur, état de départ et conditions, écrit `historique_dossier` dans la même transaction, puis met à jour. **Toute transition non listée est refusée** : 409 `ETAT_TRANSITION_INTERDITE`.

Statuts : `SOUMIS, APPROUVE, REJETE, EN_ETUDE, LISTE_NOTIFIEE, VALIDE, ORDRE_EMIS, PAYE, MEDAILLES_REMISES, CEREMONIE_PLANIFIEE, CLOTURE, ARCHIVE`.

| # | De → Vers | Acteur | Conditions et effets |
|---|---|---|---|
| T1 | ∅ → SOUMIS | DEMANDEUR (**EN_LIGNE**) ou SECRETARIAT / AGENT / CHEF (**PHYSIQUE**) | RG-DEP |
| T2 | SOUMIS → APPROUVE | **DR seul** | Dossier arrivé chez le DR |
| T3 | SOUMIS → REJETE | **DR seul** | Motif facultatif |
| T4 | APPROUVE → EN_ETUDE | AGENT ou CHEF | Prise en charge ; ligne `instruction_dossier` |
| T5 | REJETE → EN_ETUDE | Automatique (recours accepté par le DR) | RG-ECH-05 |
| T6 | EN_ETUDE → LISTE_NOTIFIEE | **CHEF seul** | Tous les récipiendaires VALIDE ou REFUSE ; ≥ 1 VALIDE ; aucun complément ENVOYEE sans réponse ; aucun recours ouvert. Génère la liste (PDF) et l'**exemple d'ordre** (RG-LIS-01) : `apercu_ordre_montant`, `apercu_ordre_detail`, `date_apercu_ordre`, `date_notification_liste`. **Tous refusés → REJETE** à la place de T6 |
| T7 | LISTE_NOTIFIEE → VALIDE | DEMANDEUR (en ligne) ou SECRETARIAT / AGENT / CHEF (**PAR_AGENT**, scan signé obligatoire) | **Confirmation unique** de la liste et de l'exemple d'ordre. Renseigne `date_acceptation_liste`, `confirmation_mode` ; crée médailles et diplômes dans la même transaction (anti-doublon). Aucun délai |
| T8 | LISTE_NOTIFIEE → EN_ETUDE | Automatique (recours accepté) | Efface l'aperçu d'ordre et la confirmation ; la prochaine T6 recalcule au tarif du jour |
| T9 | VALIDE → ORDRE_EMIS | **CHEF seul** | Montant = `apercu_ordre_montant` (sinon 409) ; `emis_par_id` = chef ; numéro attribué après signature |
| T10 | ORDRE_EMIS → PAYE | REGISSEUR ou CHEF | Quittance au montant exact et **approuvée** (RG-PAY) |
| T11 | PAYE → MEDAILLES_REMISES | REGISSEUR (automatique à la dernière remise) | Toutes les médailles du dossier remises (reste nul, `v_dossier_reste_a_remettre`) |
| T12a | MEDAILLES_REMISES → CEREMONIE_PLANIFIEE | CHEF | Cérémonie CONFIRMEE pour le dossier (RG-CER-13) |
| T12b | CEREMONIE_PLANIFIEE → CLOTURE | AGENT ou CHEF | Cérémonie TENUE, bilan complet, **tous** les VALIDE décorés (`v_dossier_bilan.nb_decores = nb_valides`) |
| T13 | CLOTURE → ARCHIVE | **CHEF seul** | `date_archivage`, `archive_par_id` ; irréversible ; lecture seule |

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-ETAT-01 `[VALIDÉ]` | Seul le **DR** approuve ou rejette (T2, T3). | 403 `ETAT_ACTEUR_NON_AUTORISE` | Ministre : 403 ; DR : succès. |
| RG-ETAT-02 `[VALIDÉ]` | Pas de statut « en recours » ni « en attente de complément » : on les **déduit** d'un recours sans décision ou d'un complément ENVOYEE sans réponse. Tant que l'un existe, toute transition est refusée, sauf la décision du recours ou la réponse au complément. | 409 `ETAT_RECOURS_EN_COURS` / `ETAT_COMPLEMENT_EN_ATTENTE` | Recours ouvert : T9 refusée. |
| RG-ETAT-03 `[VALIDÉ]` | **Recours illimités, décidés par le DR seul.** ACCEPTE → retour EN_ETUDE (T5/T8). REJETE sur une liste notifiée → la liste est maintenue. REJETE après rejet DR → le dossier reste REJETE. | — | 3 recours successifs acceptés : tous traités. |
| RG-ETAT-04 `[VALIDÉ]` | **Médailles et diplômes créés uniquement à T7**, en une transaction, à partir des métaux demandés des récipiendaires VALIDE. Avant : aucune ligne `medaille`. | 409 `ETAT_ATTRIBUTION_PREMATUREE` | Avant T7, `medaille` vide. |
| RG-ETAT-05 `[VALIDÉ]` | Chaque transition écrit `historique_dossier` (ancien, nouveau, localisation, acteur, date) dans la même transaction ; changement automatique : acteur NULL. Demandeur : statut seul ; Ministère : statut + localisation. | 500 `ETAT_HISTORIQUE_NON_ECRIT` | Transition en échec : rien écrit. |
| RG-ETAT-06 `[VALIDÉ]` | Décisions sur les récipiendaires **verrouillées après T6**, sauf retour EN_ETUDE par recours accepté. | 409 `ETAT_DECISION_VERROUILLEE` | Modifier une décision en LISTE_NOTIFIEE : 409. |
| RG-ETAT-07 `[VALIDÉ]` | **Tous les récipiendaires refusés** → le dossier devient REJETE (recours possible). | — | — |
| RG-ETAT-08 `[VALIDÉ]` | **Aucune fenêtre de contestation** : après T6, le demandeur peut confirmer (T7) ou déposer un recours **à tout moment** tant que T7 n'a pas eu lieu. Après T7, la liste est définitive. | 409 `ETAT_LISTE_DEFINITIVE` | Recours sur la liste après T7 : 409. |
| RG-ETAT-09 `[VALIDÉ]` | **Rien ne s'applique automatiquement par le silence** : pas de validation tacite. | — | — |
| RG-ETAT-10 `[VALIDÉ]` | Un récipiendaire est **décoré** si une `participation.decore = 1` existe pour lui, ou un `retrait_sans_ceremonie` abouti (`date_retrait` renseignée). Tant qu'un VALIDE n'est pas décoré, le dossier reste en CEREMONIE_PLANIFIEE. | — | — |

### 6.1 Libellés affichés `[PROPOSÉ]`

Le front n'emploie que ces libellés (aucun statut inventé côté interface) :

| Statut SQL | Libellé |
|---|---|
| SOUMIS | Soumis |
| APPROUVE | Approuvé par le DR |
| REJETE | Rejeté |
| EN_ETUDE | En étude |
| LISTE_NOTIFIEE | Liste à confirmer |
| VALIDE | Liste confirmée |
| ORDRE_EMIS | Ordre de recette émis |
| PAYE | Payé |
| MEDAILLES_REMISES | Médailles remises |
| CEREMONIE_PLANIFIEE | Cérémonie planifiée |
| CLOTURE | Clôturé |
| ARCHIVE | Archivé |

Indicateurs **déduits** (pastilles complémentaires, jamais des statuts) : « Complément demandé » (complément ENVOYEE sans réponse), « Recours en cours » (recours sans décision), « Hors délai » (RG-DEP-05), « Remise partielle » (PAYE avec reste > 0), « Rappel envoyé ».

---

## 7. Éligibilité (RG-ELIG)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-ELIG-01 `[VALIDÉ]` | **Ancienneté = année de la campagne − `annee_entree_service`**. Jour et mois ne comptent pas. | — | 2026 − 2016 = 10 ; 2017 → 9. |
| RG-ELIG-02 `[VALIDÉ]` | Seuils : **Bronze 10, Argent 20, Or 30**. Un métal est *admissible* si ancienneté ≥ seuil (plusieurs métaux possibles). | — | 35 ans → 3 métaux ; 25 → 2 ; 15 → 1 ; 8 → 0. |
| RG-ELIG-03 `[VALIDÉ]` | **Verdict informatif, jamais bloquant** : CONFORME / HORS_SEUIL_FACTEUR_MUTILATION / HORS_SEUIL. Le chef décide (l'agent donne un avis). | — | 7 ans, taux 60 → `HORS_SEUIL_FACTEUR_MUTILATION` ; validation non refusée. |
| RG-ELIG-04 `[VALIDÉ]` | `taux_mutilation` : facultatif, entier 0–100, **saisi par le demandeur** (au dépôt ou en réponse à un complément) ou par le compte qui saisit un dossier physique ; le Service ne le modifie jamais ensuite. | 422 `ELIG_TAUX_INVALIDE` | 120 / −5 : 422 ; NULL, 0, 50, 100 : ok. |
| RG-ELIG-05 `[VALIDÉ]` | **Seuil mutilé = 50 % inclus.** Facteur d'appréciation humaine, **jamais une réduction automatique** des seuils. | — | 50 → facteur ; 49 → non. |
| RG-ELIG-06 `[VALIDÉ]` | Le taux n'agit que sur le verdict de durée, jamais sur l'anti-doublon. | — | Taux 80 + métal déjà reçu : refusé. |
| RG-ELIG-07 `[VALIDÉ]` | Valider un récipiendaire hors seuil **n'exige aucun motif**. | — | — |
| RG-ELIG-08 `[VALIDÉ]` | **Remise posthume** : jusqu'à **2 ans après `date_deces`**, vérifié à la date de remise effective. | 409 `ELIG_DELAI_POSTHUME_DEPASSE` | Décès 2025-03-10 : remise 2027-03-09 ok, 2027-03-11 refusée. |
| RG-ELIG-09 `[VALIDÉ]` | **Justificatif de mutilation obligatoire** si `taux_mutilation` non NULL (`document` type JUSTIFICATIF_MUTILATION lié au récipiendaire), au dépôt et à chaque modification du taux. | 422 `ELIG_JUSTIFICATIF_MUTILATION_REQUIS` | Taux 60 sans pièce : 422. |
| RG-ELIG-10 `[VALIDÉ]` | **Le système propose, le demandeur choisit** : le formulaire pré-remplit les métaux admissibles ; le demandeur confirme ou modifie (1 à 3), y compris un métal non admissible (verdict HORS_SEUIL). | 422 `DEP_METAL_REQUIS` | 25 ans → [BRONZE, ARGENT] proposés. |
| RG-ELIG-11 `[VALIDÉ]` | Le chef valide ou refuse la **personne**, pas métal par métal : tous les métaux demandés d'un récipiendaire VALIDE sont accordés. | — | — |

---

## 8. Instruction : l'agent prépare, le chef décide (RG-INS)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-INS-01 `[VALIDÉ]` | L'agent (ou le chef) enregistre un **avis** par récipiendaire (`avis_agent` FAVORABLE / DEFAVORABLE, `avis_agent_motif`, `avis_agent_par_id`, `date_avis_agent`) ; l'avis **ne change pas** `statut_validation`. | — | Avis enregistré : statut toujours EN_ATTENTE. |
| RG-INS-02 `[VALIDÉ]` | Seul le **chef** valide ou refuse (`statut_validation`, `decide_par_id`, `date_decision`) ; refus ⇒ motif obligatoire (CHECK `ck_recipiendaire_refus`). Le chef peut décider sans avis préalable. | 403 `INS_DECISION_CHEF_SEUL` / 422 `ETAT_REFUS_SANS_MOTIF` | Agent valide : 403 ; chef refuse sans motif : 422. |
| RG-INS-03 `[VALIDÉ]` | **Compléments** : l'agent ou le chef crée un `BROUILLON` (`redige_par_id`) ; **seul le chef l'envoie** (`ENVOYEE`, `envoye_par_id`, `date_envoi`, notification) ; le demandeur répond en déposant des pièces (`REPONDUE`, `date_reponse`). Seul un complément `ENVOYEE` sans réponse bloque T6 ; les brouillons sont signalés en avertissement. Aucun délai. Un complément vise tout le dossier ou un récipiendaire. | 403 / 409 `ECH_COMPLEMENT_DEJA_REPONDU` | Agent envoie : 403 ; seconde réponse : 409. |
| RG-INS-04 `[VALIDÉ]` | Le verdict d'éligibilité reste **informatif** (RG-ELIG-03). | — | — |
| RG-INS-05 `[PROPOSÉ]` | L'**anti-doublon** est signalé dès l'instruction (avertissement visible en EN_ETUDE) pour éviter la surprise à T7. | — | Avertissement affiché si la CNI a déjà le métal chez ce demandeur. |
| RG-INS-06 `[VALIDÉ]` | **Localisation physique** : l'agent ou le chef renseigne où se trouve le dossier papier ; chaque changement est historisé (`historique_dossier` sans changement de statut, ou journal). | — | — |

---

## 9. Liste, exemple d'ordre et confirmation unique (RG-LIS)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-LIS-01 `[VALIDÉ]` | À T6, le système calcule l'**exemple d'ordre** à partir des métaux demandés des récipiendaires VALIDE : `Σ (prix_métal + prix_diplôme)` par médaille, aux **tarifs du jour figés** dans `apercu_ordre_detail` (quantité et prix par métal, diplômes, total). Il génère le PDF « Liste des récipiendaires » (validés + refusés avec motifs) incluant l'exemple d'ordre portant la mention **« exemple non officiel »**, sans numéro ni signature. | — | 1 Or + 1 Bronze → 20 000 + 13 000 + 2 × 3 000 = **39 000**, inchangé si le tarif change ensuite. |
| RG-LIS-02 `[VALIDÉ]` | Le demandeur reçoit la notification « liste et exemple d'ordre à confirmer » ; il peut **confirmer** (T7), **déposer un recours** ou écrire au Service. Aucun délai, pas de validation par silence. | — | — |
| RG-LIS-03 `[VALIDÉ]` | Confirmation **PAR_AGENT** (demandeur sans compte, ou confirmation papier) : exige `document_confirmation_id` (scan signé), `confirmation_saisie_par_id`, `confirmation_mode = PAR_AGENT` ; sinon `EN_LIGNE`. | 422 `LIS_CONFIRMATION_PREUVE_REQUISE` | Sans scan : 422 ; avec scan : VALIDE. |
| RG-LIS-04 `[VALIDÉ]` | La confirmation vaut acceptation du **montant** de l'exemple ; l'ordre officiel (T9) ne peut différer. | 409 `PAY_ORDRE_NON_CONFORME` | — |
| RG-LIS-05 `[VALIDÉ]` | Après T7, la liste est définitive (RG-ETAT-08). | 409 `ETAT_LISTE_DEFINITIVE` | — |
| RG-LIS-06 `[VALIDÉ]` | **Rappel** de liste (`liste.rappeler`, chef) : notification au demandeur pour qu'il confirme ; ne change aucun statut et ne crée **aucune** ligne `relance` (RG-ECH-07). | — | Rappel : notification, pas de ligne `relance`. |

---

## 10. Anti-doublon (RG-DOUB)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-DOUB-01 `[VALIDÉ]` | Une personne (`numero_cni`) ne reçoit **pas deux fois le même métal du même demandeur**. Vérifié à T7 par l'Action, **avant** le trigger. En cas de conflit, T7 est refusée et aucune médaille n'est créée. | 409 `DOUB_MEDAILLE_EXISTANTE` | Même CNI, même demandeur, Bronze déjà attribué : T7 refusée. |
| RG-DOUB-02 `[VALIDÉ]` | Le même métal peut être attribué à la même personne par un **autre demandeur**. | — | Bronze chez A puis chez B : ok. |
| RG-DOUB-03 `[VALIDÉ]` | Jusqu'à **3 métaux différents** par personne dans un dossier ; jamais deux fois le même (`UNIQUE (recipiendaire_id, metal)`). | 409 `DOUB_METAL_DEJA_ATTRIBUE` | Second Bronze : refusé. |
| RG-DOUB-04 `[VALIDÉ]` | Un `numero_cni` n'apparaît **qu'une fois par dossier**. | 422 `DOUB_CNI_DANS_DOSSIER` | Deux lignes de même CNI : 422. |
| RG-DOUB-05 `[VALIDÉ]` | Le trigger est aussi testé : insertion SQL directe d'un doublon → refusée, convertie en 409. | 409 `DOUB_VIOLATION_BASE` | — |

---

## 11. Échanges : recours, relances, messagerie (RG-ECH, RG-MSG)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-ECH-03 `[VALIDÉ]` | **Recours** : déposé par le demandeur (courrier généré ou scan) sur un rejet ou sur la liste notifiée ; **décidé par le DR seul**, nombre illimité ; la décision comporte `justification` (au demandeur) et `indications_decision` (au Service). Agent et chef **lisent** sans décider. | 403 `ECH_RECOURS_DR_SEUL` | Chef décide : 403. |
| RG-ECH-04 `[VALIDÉ]` | Un seul recours **ouvert** à la fois par dossier. | 409 `ECH_RECOURS_DEJA_OUVERT` | Deuxième recours sans décision : 409. |
| RG-ECH-05 `[VALIDÉ]` | La décision du recours déclenche T5 / T8 (RG-ETAT-03) dans la même transaction. | — | — |
| RG-ECH-06 `[VALIDÉ]` | **Relance après cérémonie** (`relance`) : le demandeur dont un récipiendaire est resté non décoré dépose une relance ; **il n'y a aucun choix de destinataire** : `relance.destinataire` vaut toujours `DR` (colonne conservée, figée comme `dossier.destinataire_initial`) et **le DR seul décide** ; si ACCEPTEE, une cérémonie RATTRAPAGE peut être planifiée par le chef. | 403 `ETAT_ACTEUR_NON_AUTORISE` | Relance avec destinataire DGT : refusée (422) ; Ministre décide : 403 ; DR : succès. |
| RG-ECH-07 `[VALIDÉ]` | Ne pas confondre (a) **relance** = demande du demandeur après cérémonie (table `relance`) et (b) **rappel** = message du chef pour faire confirmer la liste (RG-LIS-06). | — | — |
| RG-MSG-01 `[VALIDÉ]` | **Messagerie** : une conversation par dossier, partagée par AGENT, CHEF_SERVICE et le demandeur propriétaire (pas les demandeurs sans compte). Non destinée aux décisions (les décisions passent par les actions officielles). | 403 / 404 | Demandeur B écrit sur le dossier de A : 404. |
| RG-MSG-02 `[PROPOSÉ]` | Messages texte (longueur bornée), pièces jointes selon RG-DEP-10, accusés de lecture, non modifiables après envoi (masquage logique seulement). Tables : extension E4. | — | — |
| RG-MSG-03 `[PROPOSÉ]` | Chaque nouveau message notifie les autres participants (RG-NOTIF). Le front l'affiche dans un onglet « Échanges » du détail du dossier. | — | — |
| RG-MSG-04 `[VALIDÉ]` | Messagerie en lecture seule sur un dossier ARCHIVE. | 409 | — |

*(RG-ECH-01 et RG-ECH-02 de la v1.0 sont remplacées par RG-INS-03.)*

---

## 12. Paiement (RG-PAY)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-PAY-01 `[VALIDÉ]` | Le paiement se fait au **Trésor, hors application** ; l'application émet l'ordre et enregistre la quittance. | — | — |
| RG-PAY-02 `[VALIDÉ]` | **Tarifs** (FCFA) : Or 20 000, Argent 15 000, Bronze 13 000, Diplôme 3 000. Le **diplôme est facturé avec chaque médaille**. | — | — |
| RG-PAY-04 `[VALIDÉ]` | Un changement de tarif ne modifie ni les exemples déjà notifiés ni les ordres émis. | — | — |
| RG-PAY-05 `[VALIDÉ]` | **Montant exact** : `quittance.montant_paye` = montant de l'ordre. Il n'existe pas de paiement partiel. | 422 `PAY_MONTANT_QUITTANCE_INVALIDE` | 30 000 pour 39 000 : refusée. |
| RG-PAY-06 `[VALIDÉ]` | La quittance est **contrôlée** (approbation, attestation Trésor) ; T10 seulement si approuvée. Une quittance refusée (motif obligatoire) peut être redéposée (versions successives, extension E3). La décision aboutit toujours à approuvée ou refusée. | 409 `PAY_QUITTANCE_NON_APPROUVEE` | Quittance en attente : T10 refusée. |
| RG-PAY-10 `[VALIDÉ]` | **Seul le chef** émet l'ordre (policy + trigger `trg_ordre_chef_seul`). | 403 `PAY_ORDRE_CHEF_SEUL` | Agent émet : 403. |
| RG-PAY-11 `[VALIDÉ]` | Montant de l'ordre = `apercu_ordre_montant` confirmé (trigger) ; **un seul ordre par dossier** ; numéro attribué après signature ; PDF signé et cacheté numériquement par le chef. | 409 `PAY_ORDRE_NON_CONFORME` / `PAY_ORDRE_DEJA_EMIS` | Montant ≠ aperçu : 409 (Action et trigger). |
| RG-PAY-12 `[VALIDÉ]` | La quittance est **déposée par le demandeur** (`mode_saisie = DEPOT_DEMANDEUR`) ou **saisie par le régisseur** (`SAISIE_REGISSEUR`, `saisi_par_id`) avec numéro, date, montant et scan. | 422 | Saisie régisseur sans scan : 422. |
| RG-PAY-13 `[PAR DÉFAUT]` | **Séparation des tâches** : une quittance saisie par le régisseur est contrôlée par le **chef** ; une quittance déposée par le demandeur est contrôlée par le régisseur ou le chef. Personne ne contrôle une quittance qu'il a saisie. | 403 `PAY_CONTROLE_AUTEUR` | Régisseur contrôle sa propre saisie : 403. |
| RG-PAY-14 `[PROPOSÉ]` | L'ordre (chef) et le contrôle de la quittance (régisseur / chef) sont deux écrans distincts. | — | — |

---

## 13. Remise, stock et retrait (RG-REM, RG-STK, RG-RET)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-REM-01 `[VALIDÉ]` | Le **REGISSEUR** enregistre une remise sur un dossier **PAYE**, contre quittance approuvée. Les diplômes papier ne sont pas remis ici. | 409 `REM_DOSSIER_NON_PAYE` | Remise sur ORDRE_EMIS : 409. |
| RG-REM-03 `[VALIDÉ]` | Le retirant est identifié (nom, prénom, qualité, pièce d'identité). | 422 | — |
| RG-REM-04 `[VALIDÉ]` | Une médaille ne peut être remise qu'une fois (`medaille.remise_id`). | 409 `REM_DEJA_REMISE` | — |
| RG-REM-10 `[VALIDÉ]` | **Remise partielle** : le régisseur coche les médailles retirées (par récipiendaire) ; l'écran affiche par métal **payées / déjà remises / reçues aujourd'hui / reste**. Le serveur écrit `remise_medailles` (`saisi_par_id`), une `remise_ligne` par métal, met `medaille.remise_id` et crée un mouvement `SORTIE` (`motif_type = REMISE`, `remise_id`) par métal. | 422 `REM_QUANTITE_INCOHERENTE` | Reçues > reste : 422. |
| RG-REM-11 `[VALIDÉ]` | T11 seulement quand le reste est nul pour tous les métaux. Entre-temps le dossier reste PAYE et le reste est affiché au demandeur, à l'agent, au chef et au régisseur. | — | 2 remises successives → T11 à la seconde. |
| RG-STK-01 `[VALIDÉ]` | Toute sortie verrouille la ligne de stock (`lockForUpdate`) ; **le stock ne devient jamais négatif**. | 409 `STK_INSUFFISANT` | Stock Or à 0 : remise Or refusée, rien d'écrit. |
| RG-STK-02 `[VALIDÉ]` | Trois lignes de stock (Or, Argent, Bronze) ; `mouvement_stock` enregistre chaque entrée et sortie, jamais supprimé. Cohérence : `actuel = entrées − sorties`. | — | — |
| RG-STK-10 `[VALIDÉ]` | **Mouvements manuels** du régisseur : `type_distinction`, `sens`, `quantite > 0`, `motif_type` (`LIVRAISON` avec bon de livraison, `CORRECTION`, `PERTE`, `AUTRE`), `motif` obligatoire sauf livraison, `compte_interne_id` renseigné. Mise à jour de `stock_distinction` (entrées, sorties, date). Les mouvements des remises et retraits sont **automatiques et non modifiables** à la main. | 409 `STK_INSUFFISANT` / 422 | Sortie PERTE au-delà du stock : 409. |
| RG-STK-11 `[PROPOSÉ]` | Alerte de stock bas (seuil en configuration, 5 proposé) notifiée au régisseur et au chef. | — | — |
| RG-RET-10 `[VALIDÉ]` | **Retrait sans cérémonie** : le chef valide la demande, le régisseur remet après vérification du justificatif d'identité ; une remise par métal et par entreprise ; mouvement `SORTIE` (`motif_type = RETRAIT`, `retrait_id`). Il peut déclencher T11 et compte comme « décoré » (RG-ETAT-10). | 409 `RET_DEJA_REMIS` | Second retrait du même métal : 409. |

---

## 14. Cérémonie, délégation, bilan, archivage (RG-CER, RG-DEL, RG-BIL, RG-ARC)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-CER-01 `[VALIDÉ]` | Types : OFFICIELLE, HORS_DELAI, RATTRAPAGE. L'ADMINISTRATEUR ne paramètre que la date et le lieu de la cérémonie officielle de la campagne ; le reste est géré par le chef. | 403 | — |
| RG-CER-10 `[VALIDÉ]` | Le demandeur **propose** une cérémonie (`ceremonie_proposition` : dossier, date souhaitée ≥ aujourd'hui, lieu, message, récipiendaires) pour un dossier au moins PAYE ou pour un récipiendaire non décoré ; **une seule proposition ouverte par dossier** ; il peut l'annuler tant qu'elle est EN_ATTENTE. Un compte interne peut la saisir pour un demandeur sans compte (`saisi_par_id`). | 409 `CER_PROPOSITION_DEJA_OUVERTE` | Deuxième proposition ouverte : 409. |
| RG-CER-11 `[VALIDÉ]` | Le **chef confirme ou refuse** (refus : motif obligatoire) ; **pas de contre-proposition**. La confirmation crée ou rattache une `ceremonie` (`ceremonie_id`, `decide_par_id`) et notifie. La cérémonie officielle n'est pas modifiable par le demandeur. | 403 `CER_CHEF_SEUL` / 422 | Agent confirme : 403 ; refus sans motif : 422. |
| RG-CER-12 `[VALIDÉ]` | Le demandeur ne voit que les cérémonies où figure un de ses récipiendaires ou une de ses propositions. | 404 | — |
| RG-CER-13 `[PROPOSÉ]` | **Planifier** un dossier sur une cérémonie CONFIRMEE (chef) crée une `participation` pour chaque récipiendaire VALIDE non encore décoré, puis déclenche T12a. | — | — |
| RG-CER-14 `[VALIDÉ]` | Le chef marque la cérémonie **TENUE** (date passée) ; le bilan n'est possible qu'ensuite. | 409 | Bilan avant TENUE : 409. |
| RG-DEL-10 `[VALIDÉ]` | La **délégation est rédigée, modifiée et signée par le DR seul** (policy + trigger `trg_delegation_dr_seul`). Une délégation par (cérémonie, demandeur) ; **versionnée** (une seule active) ; une version signée et scellée ne se modifie plus (nouvelle version). Contenu éditable : `numero_reference` (sous « Direction de la Réglementation »), `libelle_entreprise` (« de la SOBRAGA »), points d'énumération, `date_fabrication`, cachet et signature numériques ; logo du Gabon en couleur identique au document scanné. | 403 `DEL_DR_SEUL` / 409 `DEL_VERSION_SCELLEE` | Chef rédige : 403 ; modifier une version scellée : 409. |
| RG-DEL-11 `[VALIDÉ]` | **Organigramme** : `membre_delegation.est_autorite = 1` exige `rang` et `metal` ; liste ordonnée par rang (1 Président → OR, 2 → ARGENT…). | 422 | — |
| RG-BIL-01 `[VALIDÉ]` | Après une cérémonie TENUE, l'**agent ou le chef** saisit le **bilan par dossier** (`bilan_ceremonie`) : soit `tous_decores = 1` (le système met `participation.decore = 1` et `date_remise_effective` pour tous les VALIDE du dossier), soit `tous_decores = 0` avec la sélection des **non décorés** (`decore = 0`, `motif_non_decore` obligatoire), les autres `decore = 1`. Un bilan peut être refait après un rattrapage (historique dans `journal_activite`). | 422 `BIL_MOTIF_REQUIS` | Non décoré sans motif : 422. |
| RG-BIL-02 `[VALIDÉ]` | T12b exige un bilan complet et `nb_decores = nb_valides`. Sinon le dossier reste ouvert. | 409 `BIL_RECIPIENDAIRES_NON_DECORES` (avec la liste) | Un non décoré : T12b refusée ; après rattrapage et nouveau bilan : acceptée. |
| RG-ARC-01 `[VALIDÉ]` | Seul le **chef** archive (T13), depuis CLOTURE : `ARCHIVE`, date, auteur, historique. Le dossier archivé est en **lecture seule**, sort des listes actives, apparaît dans **Archives** ; ses diplômes restent téléchargeables ; **pas de désarchivage**. | 409 `ARC_DOSSIER_NON_CLOTURE` / `ARC_DOSSIER_ARCHIVE_LECTURE_SEULE` | Agent archive : 403 ; écriture sur ARCHIVE : 409. |

*(RG-CER-04, RG-CER-06, RG-CER-07 et RG-DEL-01 de la v1.0 sont remplacées par RG-BIL-02, RG-CER-10, RG-CER-11 et RG-DEL-10.)*

---

## 15. Documents et fichiers (RG-DOC)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-DOC-01 `[VALIDÉ]` | **Un fichier = une fiche `document_numerise`**, rattachée à un seul objet. Fichier stocké **hors partie publique**, nom aléatoire, contenu chiffré ; jamais d'URL publique. | — | Aucune route publique vers le stockage. |
| RG-DOC-02 `[VALIDÉ]` | L'accès à un fichier passe par une **route qui vérifie les droits** et **journalise chaque accès** (`journal_activite`). | 403 / 404 | Demandeur A télécharge la pièce de B : 404 ; accès journalisé. |
| RG-DOC-03 `[VALIDÉ]` | Origine : TELEVERSE ou GENERE. Documents générés (PDF depuis Blade) : liste des récipiendaires avec exemple d'ordre, ordre de recette, délégation, diplôme, courriers. | — | — |
| RG-DOC-04 `[VALIDÉ]` | **Diplôme numérique lisible dès VALIDE** (il n'existe pas avant). Visible par DEMANDEUR (le sien), AGENT, CHEF, REGISSEUR. PDF produit à la demande, **non signé**. | 404 `DOC_DIPLOME_INDISPONIBLE` | Avant T7 : 404 ; après : 200. |
| RG-DOC-05 `[VALIDÉ]` | Document **scellé** (SIGNE_SCELLE) : plus de remplacement de fichier (trigger) ; une correction crée un **nouveau document**. | 409 `DOC_SCELLE` | — |
| RG-DOC-07 `[VALIDÉ]` | **Transmission** : le fichier ne bouge pas, seul le droit d'y accéder circule (SECRETARIAT, MINISTRE, DGT, DR). Statuts ENVOYEE → RECUE → LUE. Une transmission vise une personne ou un rôle ; adressée à un rôle, elle est visible de tous les comptes actifs de ce rôle et le premier qui la traite la prend en charge (`destinataire_id`). | 422 `DOC_TRANSMISSION_CIBLE` | Sans destinataire ni rôle : 422. |
| RG-DOC-08 `[PROPOSÉ]` | Numérotation officielle (`numero_document`) attribuée **après** signature. | — | — |
| RG-DOC-09 `[VALIDÉ]` | Les courriers du demandeur (demande, recours, relance) sont **générés dans l'application** (modèle + texte saisi) puis signés ; le téléversement d'un scan est permis en plus. | — | — |

## 16. Signatures, cachets et visas (RG-SIG)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-SIG-01 `[VALIDÉ]` | **Une seule signature ACTIVE par personne** (colonne générée + unicité). On désactive, on ne supprime jamais. | 409 `SIG_DEJA_ACTIVE` | Deuxième activation : 409. |
| RG-SIG-02 `[VALIDÉ]` | Une signature s'active par **code à usage unique** envoyé par e-mail, à durée limitée ; au-delà d'un nombre d'essais, blocage. | 429 `SIG_TROP_DE_TENTATIVES` | — |
| RG-SIG-03 `[VALIDÉ]` | Apposer une signature (`signature_apposee`) : une par document ; enregistre code, IP, navigateur, date ; le contenu est empreint **avant** numérotation. | 409 `SIG_DEJA_SIGNE` | Signer deux fois : 409. |
| RG-SIG-04 `[VALIDÉ]` | **Cachet** : image d'un service (pas d'une personne), apposée par un agent habilité (`utilisateur.cachet_id`) ; mémorise qui l'a apposé. Désactivé sans suppression. | 403 | — |
| RG-SIG-05 `[VALIDÉ]` | **Visas** : plusieurs paraphes ordonnés sur un document (`ordre_visa` unique par document). | — | — |
| RG-SIG-06 `[VALIDÉ]` | `journal_signature` est **append-only et chaîné** : `hash_courant = SHA-256(contenu de la ligne + hash_precedent)` ; commande Artisan de vérification d'intégrité. | — | Modifier une ligne : refusé ; chaîne vérifiée. |
| RG-SIG-07 `[PAR DÉFAUT]` | Signataires : le **DR** signe la délégation qu'il rédige et ses décisions ; le **chef** signe et cachette l'ordre qu'il émet et les autres documents du Service ; le demandeur signe ses courriers. Les diplômes ne sont jamais signés. | — | — |
| RG-SIG-08 `[VALIDÉ]` | Signature et cachet **numériques** (images) ; pas de certificat qualifié pour l'instant (PAdES : option future, à ne pas choisir seul). | — | — |

## 17. Notifications (RG-NOTIF)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-NOTIF-01 `[VALIDÉ]` | Une notification est créée à **chaque événement** du parcours : dépôt (en ligne et physique), transmission, approbation/rejet, prise en charge, complément envoyé/répondu, liste notifiée (avec exemple d'ordre), rappel, confirmation, ordre émis, quittance déposée/saisie/contrôlée, remise (partielle et totale), proposition de cérémonie (déposée/confirmée/refusée), cérémonie planifiée/tenue, bilan, clôture, archivage, recours déposé/décidé, relance déposée/décidée, délégation signée, nouveau message, stock bas. | — | Chaque transition → au moins une notification au bon destinataire. |
| RG-NOTIF-02 `[VALIDÉ]` | Un utilisateur ne lit que **ses** notifications. Marquage lu/non lu, « tout marquer comme lu », compteur de non lues. | 404 | — |
| RG-NOTIF-03 `[VALIDÉ]` | Centre de notifications : **rafraîchi toutes les 30 s**, toast à l'arrivée, compteur dans le titre de l'onglet, **cloche avec compteur dans la barre du haut et compteur sur l'entrée « Notifications » du menu latéral** (interface du profil test). | — | — |
| RG-NOTIF-04 `[PROPOSÉ]` | Certains événements envoient aussi un e-mail (file d'attente) ; l'échec d'e-mail **n'annule pas** la transition ; on distingue « en file », « envoyé » et « échec » (extension E5). | — | — |
| RG-NOTIF-05 `[VALIDÉ]` | Une notification d'un assistant IA mentionne l'assistant (`assistant_ia_id`). | — | — |
| RG-NOTIF-06 `[PROPOSÉ]` | Une notification liée à un dossier porte un lien vers lui (extension E5) ; le bouton « Consulter » du front l'utilise. | — | — |
| RG-NOTIF-07 `[VALIDÉ]` | Demandeur sans compte : RG-DEP-15. | — | — |

## 18. Espace demandeur (RG-DEM)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-DEM-01 `[VALIDÉ]` | **Profil** : identité et représentant modifiables (type non modifiable) ; changement d'e-mail avec nouveau code à 6 chiffres ; changement de mot de passe qui ferme les autres sessions ; liste des appareils connectés ; préférences de notification ; journal de ses propres actions. Jamais de suppression de compte. | — | Changer le mot de passe déconnecte les autres sessions. |
| RG-DEM-02 `[VALIDÉ]` | **Statistiques du demandeur** (`demandeur.statistiques`), calculées **sur ses seuls dossiers** : dossiers par statut ; récipiendaires en attente / validés / refusés ; médailles par métal, dont remises et reste à remettre ; **finances** : total des ordres, total payé et contrôlé, reste à payer, quittances en attente / refusées, tableau par dossier (ordre, payé, reste, date, état) ; cérémonies à venir / tenues / propositions en attente. Aucun chiffre calculé côté navigateur ; les 11 diagrammes globaux restent refusés. | 403 | Un autre demandeur : aucune fuite. |
| RG-DEM-03 `[VALIDÉ]` | La **CNI est masquée** dans toutes les réponses destinées au demandeur (`***-***-1234`) ; saisie complète à la création. | — | — |
| RG-DEM-04 `[VALIDÉ]` | **Archives** : dossiers CLOTURE et ARCHIVE du demandeur, lecture seule. | — | — |

## 19. Achats et approvisionnement (RG-ACH) — à valider avec le régisseur

| ID | Règle | Statut |
|---|---|---|
| RG-ACH-01 | Chaîne : budget → bon de commande (BROUILLON → PASSEE → PARTIELLEMENT_LIVREE → LIVREE / ANNULEE) → lignes → bon de livraison → **entrée de stock** (`motif_type = LIVRAISON`). | `[PROPOSÉ]` |
| RG-ACH-02 | Une livraison crée un mouvement ENTREE par ligne ; la somme livrée ne dépasse pas la quantité commandée. | `[PROPOSÉ]` |
| RG-ACH-03 | Numéros de bon de commande et de livraison uniques. | `[PROPOSÉ]` |
| RG-ACH-04 | Tant que non validée, la chaîne est **« indisponible »** dans l'interface (modèles créés, aucun écran actif, aucune donnée fictive). L'entrée manuelle `LIVRAISON` de RG-STK-10 reste possible avec un bon de livraison saisi. | `[VALIDÉ]` |

## 20. Administration (RG-ADM)

| ID | Règle | Erreur | Test attendu |
|---|---|---|---|
| RG-ADM-01 `[VALIDÉ]` | Rubriques réservées à l'ADMINISTRATEUR : campagnes (et cérémonie officielle), tarifs, référentiels, comptes et postes, reconnaissance des demandeurs, cachets, journal global, qualité et tests. | 403 | Non-admin : 403. |
| RG-ADM-02 `[VALIDÉ]` | **Référentiels** : 13 secteurs, 9 provinces, 249 pays/nationalités. Les pays viennent **uniquement** du fichier fourni `seed_pays_complet_v4.sql` (aucune liste écrite à la main), chargé par un seeder **idempotent** qui signale un conflit de libellé sans l'ignorer. | 409 `ADM_REF_CONFLIT` | Rejouer le seeder : aucun doublon. |
| RG-ADM-03 `[VALIDÉ]` | Un secteur, une province ou un pays **déjà utilisé** ne se supprime pas ; on le renomme. | 409 | — |
| RG-ADM-04 `[VALIDÉ]` | **Reconnaître un demandeur** : ADMINISTRATEUR seul, journalisé. | 403 | — |
| RG-ADM-05 `[VALIDÉ]` | Modification des tarifs : ADMINISTRATEUR seul ; sans effet rétroactif (RG-PAY-04). | 403 | — |
| RG-ADM-06 `[VALIDÉ]` | **L'ADMINISTRATEUR ne voit aucun dossier** (RG-DROIT-05) et ne prend aucune décision métier. | 403 | — |

## 21. Statistiques (RG-STAT)

| ID | Règle | Test attendu |
|---|---|---|
| RG-STAT-01 `[VALIDÉ]` | Un endpoint (ou un bloc de page) par graphique, qui lit **uniquement** la vue `v_stat_*` correspondante ; aucun calcul dans le front ni le contrôleur. | L'endpoint renvoie les lignes de sa vue. |
| RG-STAT-02 `[VALIDÉ]` | Définitions : **décoré** = médaille attribuée (dossier au moins VALIDE, ARCHIVE compris) ; **année** = année de la campagne ; **personne** = CNI distinct ; **ancienneté** = RG-ELIG-01. | C1 décorée par A et B en 2025 : 4 personnes pour 7 médailles selon le jeu de test. |
| RG-STAT-03 `[VALIDÉ]` | Secteur obligatoire pour une entreprise ; province pour tous. | Entreprise sans secteur : 422. |
| RG-STAT-04 `[VALIDÉ]` | À la **clôture de campagne**, les vues sont figées en JSON dans `archive_statistique_campagne.repartitions` (commande `campagne:snapshot`) ; jamais modifiée ensuite. | Modifier après clôture n'altère pas l'archive. |
| RG-STAT-05 `[VALIDÉ]` | `statistique_campagne` : compteurs tenus à jour à chaque événement ; **cohérence** avec les vues (médailles par métal). | Test après cycle complet. |
| RG-STAT-06 `[VALIDÉ]` | Un graphique sans données affiche un **état vide**, jamais de chiffres inventés. | Base vide : état vide. |

| Diagramme | Vue |
|---|---|
| 1 Décorations par année | `v_stat_decorations_annee` |
| 2 Hommes / femmes | `v_stat_sexe_annee` |
| 3 Médaille demandée / décernée | `v_stat_metal_annee` |
| 4 Secteur d'activité | `v_stat_secteur_annee` |
| 5 Nationalité | `v_stat_nationalite_annee` |
| 6 Province | `v_stat_province_annee` |
| 7 Ancienneté | `v_stat_anciennete_annee` |
| 8 Mutilés et posthumes | `v_stat_mutiles_posthumes_annee` |
| 9 Top demandeurs | `v_stat_top_demandeurs` |
| 10 Validation | `v_stat_validation_annee` |
| 11 Délai de traitement | `v_stat_delai_traitement_annee` |

Vues de suivi v5 : `v_dossier_reste_a_remettre` (remise partielle), `v_dossier_bilan` (décorés / validés).

## 22. Audit, qualité et sécurité (RG-AUD, RG-QUAL, RG-SEC)

| ID | Règle |
|---|---|
| RG-AUD-01 `[VALIDÉ]` | `historique_dossier` : append-only (triggers). |
| RG-AUD-02 `[VALIDÉ]` | `journal_activite` : qui, quoi, quand, **chaque accès à un fichier** ; **jamais purgé** ; aucun secret ni mot de passe dans `details` ; écrit par écouteurs d'événements, pas à la main dans les contrôleurs. |
| RG-AUD-03 `[VALIDÉ]` | Actions d'administration (campagne, compte, tarif, reconnaissance, rattachement) toujours journalisées. |
| RG-AUD-04 `[VALIDÉ]` | Journal visible : chacun ses événements ; global pour l'ADMINISTRATEUR. |
| RG-QUAL-01 `[VALIDÉ]` | Quatre tables techniques (`qualite_execution`, `qualite_resultat_test`, `qualite_erreur`, `qualite_erreur_occurrence`, extension E6) ; page « Qualité et tests » pour l'ADMINISTRATEUR. |
| RG-QUAL-02 `[VALIDÉ]` | Suites lançables depuis la page : `php-unit`, `php-feature`, `regle`, `navigation-responsive`, `toutes` (la suite `front-dom` de l'ancien dépôt devient la suite de tests de navigateur du nouveau projet). |
| RG-QUAL-03 `[VALIDÉ]` | `QUALITE_TESTS_EXECUTABLES = false` par défaut ; lancement **refusé en production** ; le lanceur refuse la base de l'application, `TestCase` aussi. |
| RG-QUAL-04 `[VALIDÉ]` | Collecte d'erreurs **masquée et bornée** (pas de donnée personnelle, pas de secret). |
| RG-QUAL-05 `[VALIDÉ]` | Rétention 90 / 30 / 90 jours ; la purge ne touche **que** ces tables de diagnostic. |
| RG-QUAL-06 `[VALIDÉ]` | Comptes de recette et mot de passe de test **uniquement** sur bases non production. |
| RG-SEC-01 `[VALIDÉ]` | Session + jeton CSRF sur toute requête d'écriture ; échec : 419. |
| RG-SEC-02 `[VALIDÉ]` | Aucune donnée injectée dans la page sans échappement (Blade `{{ }}` ; jamais `{!! !!}` sur une donnée utilisateur). |
| RG-SEC-03 `[VALIDÉ]` | Aucune CNI ni donnée sensible inutile exposée au navigateur. |
| RG-SEC-04 `[PROPOSÉ]` | En-têtes de sécurité (CSP, X-Frame-Options, X-Content-Type-Options) ; HTTPS obligatoire en production ; aucune ressource chargée depuis un CDN (polices hébergées localement). |
| RG-SEC-05 `[VALIDÉ]` | Secrets (mots de passe, codes) jamais journalisés ni renvoyés après création. |
| RG-SEC-06 `[PROPOSÉ]` | Sauvegarde quotidienne de la base et des fichiers ; test de restauration documenté. |
| RG-SEC-07 `[PROPOSÉ]` | Données personnelles (CNI, noms) : accès restreint aux profils qui en ont besoin ; mention d'information dans les conditions d'utilisation. |

---

## 23. Codes d'erreur (index)

| Code | HTTP | Règle |
|---|---|---|
| `VALIDATION` | 422 | RG-ARCH-11 |
| `DROIT_INTERDIT` | 403 | RG-DROIT-01 |
| `ARCH_DOUBLE_ENVOI` | 409 | RG-ARCH-14 |
| `ARCH_BASE_APPLICATION` | 500 | RG-ARCH-10 |
| `*_VIOLATION_BASE` | 409 | RG-ARCH-06 |
| `AUTH_EMAIL_NON_VERIFIE` | 403 | RG-AUTH-02 |
| `AUTH_POSTE_INCOHERENT` | 422 | RG-AUTH-05 |
| `AUTH_DERNIER_ADMIN`, `AUTH_AUTO_DESACTIVATION` | 409 | RG-AUTH-06 |
| `AUTH_TROP_DE_TENTATIVES` | 429 | RG-AUTH-07 |
| `CAMP_ANNEE_EXISTANTE`, `CAMP_DATES_INCOHERENTES` | 422 | RG-CAMP |
| `CAMP_VERROUILLEE` | 409 | RG-CAMP-05 |
| `DEP_DEMANDEUR_NON_RECONNU` | 403 | RG-DEP-01 |
| `DEP_PIECES_MANQUANTES`, `DEP_METAL_REQUIS`, `DEP_CHAMP_STATISTIQUE_REQUIS`, `DEP_ANNEE_ENTREE_INVALIDE`, `DEP_PIECE_INVALIDE`, `DEP_MODE_DEPOT_REQUIS`, `DEP_IMPORT_INVALIDE` | 422 | RG-DEP |
| `DEP_DOSSIER_VERROUILLE`, `DEP_DEMANDEUR_PROBABLE_DOUBLON`, `DEP_BROUILLON_DEJA_ACTIF` | 409 | RG-DEP |
| `ETAT_TRANSITION_INTERDITE`, `ETAT_RECOURS_EN_COURS`, `ETAT_COMPLEMENT_EN_ATTENTE`, `ETAT_ATTRIBUTION_PREMATUREE`, `ETAT_DECISION_VERROUILLEE`, `ETAT_LISTE_DEFINITIVE` | 409 | RG-ETAT |
| `ETAT_ACTEUR_NON_AUTORISE` | 403 | RG-ETAT-01 |
| `ETAT_REFUS_SANS_MOTIF` | 422 | RG-INS-02 |
| `ETAT_HISTORIQUE_NON_ECRIT` | 500 | RG-ETAT-05 |
| `ELIG_TAUX_INVALIDE`, `ELIG_JUSTIFICATIF_MUTILATION_REQUIS` | 422 | RG-ELIG |
| `ELIG_DELAI_POSTHUME_DEPASSE` | 409 | RG-ELIG-08 |
| `INS_DECISION_CHEF_SEUL` | 403 | RG-INS, RG-DROIT-02 |
| `LIS_CONFIRMATION_PREUVE_REQUISE` | 422 | RG-LIS-03 |
| `DOUB_MEDAILLE_EXISTANTE`, `DOUB_METAL_DEJA_ATTRIBUE`, `DOUB_VIOLATION_BASE` | 409 | RG-DOUB |
| `DOUB_CNI_DANS_DOSSIER` | 422 | RG-DOUB-04 |
| `ECH_COMPLEMENT_DEJA_REPONDU`, `ECH_RECOURS_DEJA_OUVERT` | 409 | RG-INS-03, RG-ECH-04 |
| `ECH_RECOURS_DR_SEUL` | 403 | RG-ECH-03 |
| `PAY_ORDRE_CHEF_SEUL`, `PAY_CONTROLE_AUTEUR` | 403 | RG-PAY |
| `PAY_ORDRE_DEJA_EMIS`, `PAY_ORDRE_NON_CONFORME`, `PAY_QUITTANCE_NON_APPROUVEE` | 409 | RG-PAY |
| `PAY_MONTANT_QUITTANCE_INVALIDE` | 422 | RG-PAY-05 |
| `REM_DOSSIER_NON_PAYE`, `REM_DEJA_REMISE`, `STK_INSUFFISANT`, `RET_DEJA_REMIS` | 409 | RG-REM, RG-STK, RG-RET |
| `REM_QUANTITE_INCOHERENTE` | 422 | RG-REM-10 |
| `CER_PROPOSITION_DEJA_OUVERTE` | 409 | RG-CER-10 |
| `CER_CHEF_SEUL`, `DEL_DR_SEUL` | 403 | RG-CER-11, RG-DEL-10 |
| `DEL_VERSION_SCELLEE` | 409 | RG-DEL-10 |
| `BIL_MOTIF_REQUIS` | 422 | RG-BIL-01 |
| `BIL_RECIPIENDAIRES_NON_DECORES` | 409 | RG-BIL-02 |
| `ARC_DOSSIER_NON_CLOTURE`, `ARC_DOSSIER_ARCHIVE_LECTURE_SEULE` | 409 | RG-ARC-01 |
| `DOC_DIPLOME_INDISPONIBLE` | 404 | RG-DOC-04 |
| `DOC_SCELLE` | 409 | RG-DOC-05 |
| `DOC_TRANSMISSION_CIBLE` | 422 | RG-DOC-07 |
| `SIG_DEJA_ACTIVE`, `SIG_DEJA_SIGNE` | 409 | RG-SIG |
| `SIG_TROP_DE_TENTATIVES` | 429 | RG-SIG-02 |
| `ADM_REF_CONFLIT` | 409 | RG-ADM-02 |

---

## 24. Extensions de schéma

Le SQL v4 + migration v5 reste la référence. Les extensions ci-dessous sont **autorisées** ; chacune est une migration **additive** séparée, justifiée dans `docs/DECISIONS.md`, et le test de comparaison du schéma en tient compte. Toute autre colonne ou table n'est ajoutée que si une règle de ce document est impossible à respecter sans elle (même procédure, signalée dans le rapport final).

| # | Extension | Statut | Contenu minimal |
|---|---|---|---|
| E1 | Comptes (`utilisateur`) | `[VALIDÉ]` | `est_actif` BOOL NOT NULL DEFAULT 1, `doit_changer_mot_de_passe` BOOL NOT NULL DEFAULT 0, `date_desactivation` DATETIME NULL, `desactive_par_id` FK `utilisateur` RESTRICT, `email_verified_at` DATETIME NULL, `remember_token` VARCHAR(100) NULL. Le modèle `Utilisateur` utilise `login` comme identifiant et `mot_de_passe_hash` comme mot de passe. |
| E2 | Codes à usage unique | `[PROPOSÉ]` | Table `code_verification` : `utilisateur_id`, `objet` (VERIFICATION_EMAIL, REINITIALISATION, CHANGEMENT_EMAIL), `code_hash`, `expire_le`, `nb_tentatives`, `utilise_le`, `nouvel_email` NULL. Les codes de signature restent dans `signature` / `signature_apposee`. |
| E3 | Contrôle et versions de la quittance | `[PAR DÉFAUT]` (Q7) | Colonnes `statut_controle` (EN_ATTENTE, APPROUVEE, REFUSEE ; NULL + CHECK, RG-ARCH-11), `controle_par_id`, `date_controle`, `motif_refus_controle`, `attestation_tresor_document_id` NULL. Versions successives : remplacer `uq_quittance_ordre` par une colonne générée `active_pour_ordre_id = IF(statut_controle <> 'REFUSEE', ordre_de_recette_id, NULL)` + UNIQUE (même mécanisme que `uq_signature_un_actif`). **Seule exception autorisée à la règle « aucune clé existante modifiée »**, si Q7 est confirmée. |
| E4 | Messagerie | `[PROPOSÉ]` | `message_dossier` (`dossier_id`, `auteur_id` → `utilisateur`, `contenu`, `date_envoi`, `est_masque`, `document_numerise_id` NULL) et `message_lecture` (`message_id`, `utilisateur_id`, `date_lecture`). |
| E5 | Notification enrichie | `[PROPOSÉ]` | `notification` : `type_evenement` VARCHAR(60) NULL, `dossier_id` NULL FK, `statut_mail` (NON_PREVU, EN_FILE, ENVOYE, ECHEC) NULL. |
| E6 | Qualité | `[VALIDÉ]` (noms) | `qualite_execution`, `qualite_resultat_test`, `qualite_erreur`, `qualite_erreur_occurrence` : colonnes à concevoir selon RG-QUAL. |
| E7 | Préférences et idempotence | `[PROPOSÉ]` | `preference_utilisateur` (`utilisateur_id`, `cle`, `valeur` JSON) ; `cle_idempotence` (`cle`, `utilisateur_id`, `action`, `reponse`, `date`) ou cache, au choix justifié. |
| E8 | Tables techniques Laravel | `[VALIDÉ]` | `sessions` (pilote `database`, pour lister et fermer les appareils connectés), `cache`, `cache_locks`, `jobs`, `job_batches`, `failed_jobs`. |

---

## 25. Décisions prises (historique)

- **15–19 oct.** Ancienneté à l'année ; métaux proposés par le système, choisis par le demandeur (1–3) ; acceptation explicite de la liste ; pas de motif hors seuil ; justificatif de mutilation obligatoire ; diplôme facturé avec chaque médaille ; quittance au montant exact ; tous refusés → REJETE ; le Service ne modifie pas le taux de mutilation.
- **20–21 oct.** Matrice du Service ; M1 à M12 (dates de campagne, référentiels, comptes, tableau de bord qualité…) ; contrôle du paiement (approbation + attestation Trésor).
- **22–23 oct.** Remise, stock, cérémonie, retrait, diplôme ; recours décidé par le DR seul ; statistiques par profil ; notifications ; messagerie.
- **24 oct.** Suppression de tout délai de contestation ; diplôme lisible dès VALIDE ; `destinataire_initial` = DR.
- **25 oct. (v5)** INSPECTEUR supprimé ; l'agent prépare, le chef décide ; dépôt physique et demandeur sans compte ; représentant figé ; brouillon et import ; confirmation unique avec exemple d'ordre ; ordre par le chef seul ; délégation par le DR seul ; remise partielle et stock manuel ; bilan, archivage ; propositions de cérémonie sans contre-proposition ; espace demandeur avec finances.
- **26 oct. (v2.0)** Nouveau projet Laravel vierge ; un seul profil SECRETARIAT ; aucun choix de destinataire (dossiers, recours, relances : DR) ; liste des pays fournie (`seed_pays_complet_v4.sql`) ; interface du profil test (menu latéral) ; l'agent de développement crée les écrans manquants dans la charte.

## 26. Questions ouvertes — avec la valeur appliquée par défaut

| # | Question | Défaut appliqué |
|---|---|---|
| Q1 | Dépôt après la date limite : accepté « hors délai » ou refusé sauf prorogation ? | Accepté et marqué hors délai (RG-DEP-05). |
| Q2 | Le régisseur voit-il tous les dossiers ou seulement ceux en paiement / remise ? | Statut ORDRE_EMIS et suivants (RG-DROIT-05). |
| Q3 | Qui signe et cachette ? | DR : délégation et décisions ; chef : ordre et documents du Service (RG-SIG-07). |
| Q4 | Chaîne d'achat. | « Indisponible » (RG-ACH-04). |
| Q5 | Durée d'inactivité, taille maximale des pièces, seuil d'alerte de stock, nombre de lignes d'import. | 30 min, 10 Mo, 5, 500 lignes (configuration). |
| Q6 | Format du numéro de dossier. | `DIST-{année}-{5 chiffres}`. |
| Q7 | Versions de la quittance : modifier l'unicité `uq_quittance_ordre` (E3) ou garder une seule quittance par ordre (une quittance refusée est remplacée en place, historique dans le journal) ? | Modification par colonne générée (E3). |
| Q9 | Séparation des tâches sur la quittance. | Saisie par le régisseur → contrôlée par le chef (RG-PAY-13). |
| Q10 | Confirmation papier (PAR_AGENT). | Enregistrée par secrétariat, agent ou chef, scan obligatoire. |
| Q12 | Libellés de statuts (section 6.1). | Ceux de la section 6.1. |
| Q13 | Non décorés : clôture avec exception possible ? | Non : le dossier reste ouvert (RG-BIL-02). |
| Q14 | Désarchivage. | Interdit (RG-ARC-01). |

## 27. Couverture de test

Chaque règle `[VALIDÉ]`, `[PROPOSÉ]` ou `[PAR DÉFAUT]` porte son ID dans le nom d'au moins un test : cas nominal, refus par profil (403 / 404), état incompatible (409), validation (422). Un test de bout en bout couvre le parcours complet T1 → T13, en ligne et en physique, avec remise partielle, bilan avec un non décoré puis rattrapage. Les tests unitaires couvrent tous les codes de la section 23.
