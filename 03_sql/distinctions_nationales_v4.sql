-- =====================================================================
--  Gestion des distinctions nationales : base de données complète
--  Ministère du Travail du Gabon : médailles et diplômes du travail
--  Cible : MySQL 8.0+ (InnoDB, utf8mb4). Compatible MariaDB 10.5+.
--  Source : diagramme de classes v7 et dictionnaire expliqué (41 classes).
--  VERSION 4 (19 oct. 2026 soir) : v3 + destinataire figé à DR, saisie possible par secrétariat.
--
--  Changements de la v4 par rapport à la v3 (voir regles_back_bloc1 v0.4 / v0.5)
--   N13. dossier.destinataire_initial figé à 'DR' (DEFAULT 'DR') : toutes les
--        demandes arrivent au secrétariat du DR ; plus de choix MINISTRE/DGT/DR.
--   N14. saisie d'un dossier pour un demandeur reconnu : possible aussi par un
--        compte SECRETARIAT (en plus de AGENT / CHEF_SERVICE du Service).
--
--  VERSION 3 (19 oct. 2026) : v2 + rôles du Service, pays, plus de délai de contestation.
--
--  Changements de la v2 par rapport à la v1 (voir aussi regles_back_bloc1 v0.2)
--   N1. recipiendaire.taux_mutilation (0-100, facultatif) ; justificatif
--       obligatoire si renseigné -> document.recipiendaire_id (règle applicative).
--   N2. recipiendaire.date_entree_service remplacée par annee_entree_service :
--       l'ancienneté se compte en années (année de la campagne - année d'entrée).
--   N3. Table distinction_demandee : métaux demandés par récipiendaire (le
--       système en propose, le demandeur confirme ; jusqu'à 3 par personne).
--   N4. dossier : statut LISTE_NOTIFIEE + dates de notification, de limite de
--       contestation (3 jours) et d'acceptation explicite du demandeur.
--   N5. Référentiels pour des statistiques exactes : secteur_activite,
--       province, nationalite (fini les textes libres dans les graphiques).
--       recipiendaire.sexe (par CHECK) et nationalite_id deviennent obligatoires.
--   N6. historique_dossier (append-only) : historique du dossier et délais.
--   N7. recipiendaire : un même CNI une seule fois par dossier.
--   N8. 11 vues v_stat_* + la vue de base v_decoration pour les graphiques ;
--       archive_statistique_campagne.repartitions (JSON) fige les répartitions.
--
--  Changements de la v3 par rapport à la v2 (voir regles_back_bloc1 v0.3 et bloc 2)
--   N9.  compte_interne.poste (texte libre) remplacé par poste_service ENUM
--        ('AGENT','INSPECTEUR','CHEF_SERVICE'), obligatoire pour le rôle
--        SERVICE_DISTINCTIONS et interdit pour les autres rôles (CHECK).
--   N10. dossier.date_limite_contestation SUPPRIMÉE : il n'y a pas de délai.
--        Le dossier attend l'acceptation explicite du demandeur (dossier.
--        date_acceptation_liste) ; la contestation reste possible jusque-là.
--   N11. dossier.saisi_par_id (NULL = déposé par le demandeur lui-même) :
--        un agent du Service peut saisir un dossier pour un demandeur reconnu.
--        (v4 N14 : aussi un secrétariat)
--   N12. nationalite.pays ajoutée : le formulaire propose la liste des pays,
--        les graphiques affichent le libellé de nationalité.
--
--  Conventions
--   - Une classe = une table, nom en snake_case (Dossier -> dossier).
--   - Clé primaire : id BIGINT UNSIGNED AUTO_INCREMENT, sauf clés naturelles
--     (stock_distinction, tarif, ligne_commande).
--   - Une liaison = une clé étrangère, placée du côté « plusieurs ».
--     Minimum 1 côté « un » -> NOT NULL ; minimum 0 -> NULL possible.
--   - Liaison 0..1 - 0..1 (« fichier ») -> colonne UNIQUE et NULL possible.
--   - Aucune suppression en cascade (ON DELETE RESTRICT), sauf la table de
--     jonction instruction_dossier : la cascade se décidera table par table.
--
--  Écarts assumés avec le dictionnaire (à relire)
--   1. dossier.numero : le cahier des interfaces parle du numéro de dossier.
--   2. compte_interne.role contient ADMINISTRATEUR (rôle encore à confirmer) ;
--      compte_interne.poste_service distingue agent / inspecteur / chef (v3).
--   3. recours.date_recours : nécessaire pour ordonner les recours.
--   4. retrait_sans_ceremonie.compte_interne_id est NULL tant que le
--      régisseur n'a pas vérifié la demande.
--   5. Liaison n° 4 devenue 0..* - 0..* : table de jonction instruction_dossier.
--   6. Les statuts de ceremonie et de bon_commande ne sont pas fixés
--      dans le dictionnaire : valeurs proposées.
-- =====================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE DATABASE IF NOT EXISTS distinctions_nationales
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE distinctions_nationales;

-- Nettoyage pour rejouer le script (ordre sans importance, contraintes coupées)
DROP VIEW IF EXISTS
  v_stat_delai_traitement_annee, v_stat_validation_annee, v_stat_top_demandeurs,
  v_stat_mutiles_posthumes_annee, v_stat_anciennete_annee, v_stat_province_annee,
  v_stat_nationalite_annee, v_stat_secteur_annee, v_stat_metal_annee,
  v_stat_sexe_annee, v_stat_decorations_annee, v_decoration;

DROP TABLE IF EXISTS
  historique_dossier, distinction_demandee, nationalite, province, secteur_activite,
  journal_signature, visa_apposee, visa, signature_apposee, signature, transmission,
  journal_activite, notification, assistant_ia, archive_statistique_campagne,
  statistique_campagne, mouvement_stock, bon_livraison, ligne_commande, bon_commande,
  budget_achat, fournisseur, tarif, stock_distinction, remise_medailles,
  retrait_sans_ceremonie, membre_delegation, document_delegation, participation,
  ceremonie, quittance, ordre_de_recette, document, relance, recours,
  demande_complement, diplome_du_travail, medaille, recipiendaire,
  instruction_dossier, dossier, document_numerise, campagne, demandeur,
  compte_interne, utilisateur, cachet;

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- 9 (en premier car utilisateur et document_numerise y renvoient) : CACHET
-- =====================================================================
CREATE TABLE cachet (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  libelle             VARCHAR(150)    NOT NULL,                 -- ex. « Service des Distinctions »
  chemin_fichier      VARCHAR(255)    NOT NULL,                 -- image chiffrée, hors dossier public
  nom_fichier_origine VARCHAR(255)    NOT NULL,
  mime_type           VARCHAR(100)    NOT NULL,
  empreinte_fichier   CHAR(64)        NOT NULL,                 -- SHA-256 de l'image
  statut              ENUM('ACTIF','DESACTIVE') NOT NULL DEFAULT 'ACTIF',
  date_creation       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_desactivation  DATETIME        NULL,
  motif_desactivation VARCHAR(255)    NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB COMMENT='Cachet d''un service ou d''une fonction (pas d''une personne)';

-- =====================================================================
-- 0. RÉFÉRENTIELS (listes fermées : indispensables pour des graphiques exacts)
-- =====================================================================
CREATE TABLE secteur_activite (
  id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  libelle  VARCHAR(150)    NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_secteur_libelle (libelle)
) ENGINE=InnoDB COMMENT='Secteur d''activité d''une entreprise (liste gérée par l''administrateur)';

CREATE TABLE province (
  id   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom  VARCHAR(80)     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_province_nom (nom)
) ENGINE=InnoDB COMMENT='Province du siège du demandeur (graphique géographique)';

CREATE TABLE nationalite (
  id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  code_iso  CHAR(2)         NOT NULL,                           -- ISO 3166-1 alpha-2 du pays
  pays      VARCHAR(80)     NOT NULL,                           -- ex. « Gabon » (ce que le demandeur choisit dans la liste)
  libelle   VARCHAR(80)     NOT NULL,                           -- ex. « Gabonaise » (ce qu'affichent les graphiques)
  PRIMARY KEY (id),
  UNIQUE KEY uq_nationalite_code (code_iso),
  UNIQUE KEY uq_nationalite_pays (pays),
  UNIQUE KEY uq_nationalite_libelle (libelle)
) ENGINE=InnoDB COMMENT='Nationalité d''un récipiendaire (liste complète chargée par un seeder)';

-- =====================================================================
-- 1. UTILISATEURS ET DEMANDEURS
-- =====================================================================
CREATE TABLE utilisateur (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  login                 VARCHAR(100)    NOT NULL,
  mot_de_passe_hash     VARCHAR(255)    NOT NULL,               -- jamais en clair
  date_creation_compte  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  dernier_acces         DATETIME        NULL,
  cachet_id             BIGINT UNSIGNED NULL,                   -- n° 62 : cachet que l'agent est habilité à utiliser
  PRIMARY KEY (id),
  UNIQUE KEY uq_utilisateur_login (login),
  KEY idx_utilisateur_cachet (cachet_id),
  CONSTRAINT fk_utilisateur_cachet FOREIGN KEY (cachet_id) REFERENCES cachet (id)
) ENGINE=InnoDB COMMENT='Compte de connexion commun (agent ou demandeur)';

CREATE TABLE compte_interne (                                   -- n° 1 : 0..1 - 1 vers utilisateur
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  utilisateur_id BIGINT UNSIGNED NOT NULL,
  nom            VARCHAR(100)    NOT NULL,
  prenom         VARCHAR(100)    NOT NULL,
  role           ENUM('SECRETARIAT','MINISTRE','DGT','DR','SERVICE_DISTINCTIONS','REGISSEUR','ADMINISTRATEUR') NOT NULL,
  poste_service  ENUM('AGENT','INSPECTEUR','CHEF_SERVICE') NULL, -- Service des distinctions seulement (ck_ci_poste)
  PRIMARY KEY (id),
  UNIQUE KEY uq_compte_interne_utilisateur (utilisateur_id),
  CONSTRAINT fk_compte_interne_utilisateur FOREIGN KEY (utilisateur_id) REFERENCES utilisateur (id),
  CONSTRAINT ck_ci_poste CHECK (
    (role = 'SERVICE_DISTINCTIONS' AND poste_service IS NOT NULL)
    OR (role <> 'SERVICE_DISTINCTIONS' AND poste_service IS NULL))
) ENGINE=InnoDB COMMENT='Profil d''un agent du Ministère';

CREATE TABLE demandeur (                                        -- n° 2 : 0..1 - 1 vers utilisateur
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  utilisateur_id   BIGINT UNSIGNED NOT NULL,
  nom              VARCHAR(200)    NOT NULL,
  adresse          VARCHAR(255)    NULL,
  est_reconnu      TINYINT(1)      NOT NULL DEFAULT 0,          -- seuls les reconnus peuvent déposer
  type_demandeur   ENUM('ENTREPRISE','MINISTERE') NOT NULL,
  nif              VARCHAR(50)     NULL,                        -- entreprise seulement
  secteur_activite_id BIGINT UNSIGNED NULL,                     -- entreprise seulement (référentiel)
  province_id      BIGINT UNSIGNED NULL,                        -- province du siège (référentiel)
  sigle            VARCHAR(30)     NULL,                        -- ministère seulement
  PRIMARY KEY (id),
  UNIQUE KEY uq_demandeur_utilisateur (utilisateur_id),
  KEY idx_demandeur_secteur (secteur_activite_id),
  KEY idx_demandeur_province (province_id),
  CONSTRAINT fk_demandeur_utilisateur FOREIGN KEY (utilisateur_id)       REFERENCES utilisateur (id),
  CONSTRAINT fk_demandeur_secteur     FOREIGN KEY (secteur_activite_id)  REFERENCES secteur_activite (id),
  CONSTRAINT fk_demandeur_province    FOREIGN KEY (province_id)          REFERENCES province (id)
) ENGINE=InnoDB COMMENT='Entreprise ou ministère qui demande des distinctions';

-- =====================================================================
-- 2. CAMPAGNE, DOSSIER, RÉCIPIENDAIRES
-- =====================================================================
CREATE TABLE campagne (
  id                          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  annee                       SMALLINT UNSIGNED NOT NULL,
  date_debut_depot            DATE NOT NULL,                    -- par défaut 10 janvier
  date_fin_depot              DATE NOT NULL,                    -- par défaut 31 mars, prorogeable
  date_ceremonie_officielle   DATE NULL,                        -- modifiable chaque année
  lieu_officiel               VARCHAR(200) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_campagne_annee (annee),
  CONSTRAINT ck_campagne_depot CHECK (date_fin_depot >= date_debut_depot)
) ENGINE=InnoDB COMMENT='Édition annuelle du processus';

-- Fiche de fichier (créée tôt car beaucoup de tables y renvoient)
CREATE TABLE document_numerise (
  id                      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom_fichier             VARCHAR(255) NOT NULL,
  chemin_fichier          VARCHAR(255) NOT NULL,                -- nom UUID, hors dossier public, chiffré
  format_fichier          VARCHAR(20)  NOT NULL,
  date_scan               DATETIME     NULL,
  date_enregistrement     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  origine                 ENUM('TELEVERSE','GENERE') NOT NULL,
  statut_signature        ENUM('NON_SIGNE','SIGNE_VISUELLEMENT','SIGNE_SCELLE') NOT NULL DEFAULT 'NON_SIGNE',
  date_apposition_cachet  DATETIME     NULL,
  numero_document         VARCHAR(50)  NULL,                    -- numéro ajouté après la signature
  date_numerotation       DATETIME     NULL,
  cachet_id               BIGINT UNSIGNED NULL,                 -- n° 63
  cachet_appose_par_id    BIGINT UNSIGNED NULL,                 -- n° 64 (copie figée)
  PRIMARY KEY (id),
  KEY idx_dn_cachet (cachet_id),
  KEY idx_dn_cachet_par (cachet_appose_par_id),
  CONSTRAINT fk_dn_cachet     FOREIGN KEY (cachet_id)            REFERENCES cachet (id),
  CONSTRAINT fk_dn_cachet_par FOREIGN KEY (cachet_appose_par_id) REFERENCES utilisateur (id)
) ENGINE=InnoDB COMMENT='Fiche d''un fichier stocké (téléversé ou généré), sans le contenu';

CREATE TABLE dossier (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  numero                 VARCHAR(30)  NOT NULL,                 -- donné au dépôt (accusé)
  demandeur_id           BIGINT UNSIGNED NOT NULL,              -- n° 3
  campagne_id            BIGINT UNSIGNED NOT NULL,              -- n° 5
  date_depot             DATETIME     NOT NULL,
  statut                 ENUM('SOUMIS','APPROUVE','REJETE','EN_ETUDE','LISTE_NOTIFIEE','VALIDE','ORDRE_EMIS','PAYE',
                              'MEDAILLES_REMISES','CEREMONIE_PLANIFIEE','CLOTURE') NOT NULL DEFAULT 'SOUMIS',
  localisation_physique  VARCHAR(150) NULL,                     -- visible côté Ministère seulement
  destinataire_initial   ENUM('MINISTRE','DGT','DR') NOT NULL DEFAULT 'DR',  -- figé à DR (N13) : toutes les demandes vont au secrétariat du DR
  date_notification_liste  DATETIME NULL,                       -- le demandeur reçoit la liste des validés/refusés
  date_acceptation_liste   DATETIME NULL,                       -- acceptation explicite du demandeur (aucun délai : le dossier attend)
  saisi_par_id             BIGINT UNSIGNED NULL,                -- compte_interne qui a saisi le dossier (SECRETARIAT, AGENT ou CHEF_SERVICE) ; NULL = demandeur lui-même
  PRIMARY KEY (id),
  UNIQUE KEY uq_dossier_numero (numero),
  KEY idx_dossier_demandeur (demandeur_id),
  KEY idx_dossier_campagne (campagne_id),
  KEY idx_dossier_statut (statut),
  KEY idx_dossier_saisi_par (saisi_par_id),
  CONSTRAINT fk_dossier_saisi_par FOREIGN KEY (saisi_par_id) REFERENCES compte_interne (id),
  CONSTRAINT fk_dossier_demandeur FOREIGN KEY (demandeur_id) REFERENCES demandeur (id),
  CONSTRAINT fk_dossier_campagne  FOREIGN KEY (campagne_id)  REFERENCES campagne (id)
) ENGINE=InnoDB COMMENT='Demande d''un demandeur : pièce centrale. Dépôt minimal exigé : courrier + liste (règle applicative)';

CREATE TABLE instruction_dossier (                              -- n° 4 : CompteInterne 0..* - 0..* Dossier
  dossier_id                  BIGINT UNSIGNED NOT NULL,
  compte_interne_id           BIGINT UNSIGNED NOT NULL,
  date_premiere_intervention  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (dossier_id, compte_interne_id),
  KEY idx_instruction_compte (compte_interne_id),
  CONSTRAINT fk_instruction_dossier FOREIGN KEY (dossier_id)        REFERENCES dossier (id) ON DELETE CASCADE,
  CONSTRAINT fk_instruction_compte  FOREIGN KEY (compte_interne_id) REFERENCES compte_interne (id)
) ENGINE=InnoDB COMMENT='Agents du Service qui sont intervenus sur le dossier';

CREATE TABLE recipiendaire (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id            BIGINT UNSIGNED NOT NULL,               -- n° 6 : 1..* (au moins un à la création du dossier)
  numero_cni            VARCHAR(30)  NOT NULL,
  nom                   VARCHAR(100) NOT NULL,
  prenom                VARCHAR(100) NOT NULL,
  poste                 VARCHAR(150) NULL,
  annee_entree_service  SMALLINT UNSIGNED NOT NULL,             -- ancienneté = année de la campagne - cette année (l'année suffit)
  nationalite_id        BIGINT UNSIGNED NOT NULL,               -- référentiel (obligatoire : sert aux statistiques)
  sexe                  ENUM('M','F') NULL,                     -- OBLIGATOIRE (ck_recipiendaire_sexe). Pas NOT NULL : un ENUM NOT NULL omis
                                                                -- à l'insertion prend silencieusement 'M' et fausserait le graphique H/F
  taux_mutilation       TINYINT UNSIGNED NULL,                  -- NULL = non concerné ; 0-100 ; saisi par le demandeur ; justificatif obligatoire si renseigné
  statut_validation     ENUM('EN_ATTENTE','VALIDE','REFUSE') NOT NULL DEFAULT 'EN_ATTENTE',
  motif_refus           VARCHAR(500) NULL,
  date_deces            DATE         NULL,                      -- remise posthume dans les 2 ans
  PRIMARY KEY (id),
  UNIQUE KEY uq_recipiendaire_dossier_cni (dossier_id, numero_cni),   -- une même personne une seule fois par dossier
  KEY idx_recipiendaire_dossier (dossier_id),
  KEY idx_recipiendaire_cni (numero_cni),
  KEY idx_recipiendaire_nationalite (nationalite_id),
  CONSTRAINT fk_recipiendaire_dossier     FOREIGN KEY (dossier_id)     REFERENCES dossier (id),
  CONSTRAINT fk_recipiendaire_nationalite FOREIGN KEY (nationalite_id) REFERENCES nationalite (id),
  CONSTRAINT ck_recipiendaire_refus CHECK (statut_validation <> 'REFUSE' OR motif_refus IS NOT NULL),
  CONSTRAINT ck_recipiendaire_taux  CHECK (taux_mutilation IS NULL OR taux_mutilation BETWEEN 0 AND 100),
  CONSTRAINT ck_recipiendaire_sexe  CHECK (sexe IS NOT NULL),
  CONSTRAINT ck_recipiendaire_annee CHECK (annee_entree_service BETWEEN 1900 AND 2100)
) ENGINE=InnoDB COMMENT='Employé proposé dans un dossier précis (validé ou refusé seul)';

-- Métaux demandés pour un récipiendaire (avant toute attribution).
-- Le système propose les métaux admissibles d'après l'ancienneté ; le demandeur confirme.
CREATE TABLE distinction_demandee (
  recipiendaire_id BIGINT UNSIGNED NOT NULL,
  metal            ENUM('OR','ARGENT','BRONZE') NOT NULL,
  PRIMARY KEY (recipiendaire_id, metal),                        -- jamais deux fois le même métal pour un récipiendaire
  CONSTRAINT fk_dd_recipiendaire FOREIGN KEY (recipiendaire_id) REFERENCES recipiendaire (id)
) ENGINE=InnoDB COMMENT='Métaux demandés (1 à 3 par récipiendaire, au moins 1 : règle applicative) ; source du graphique « médaille la plus demandée »';

-- Historique du dossier : une ligne à chaque changement de statut ou de localisation.
-- Côté demandeur on n'affiche que le statut ; côté Ministère, statut + localisation.
CREATE TABLE historique_dossier (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id            BIGINT UNSIGNED NOT NULL,
  statut_ancien         ENUM('SOUMIS','APPROUVE','REJETE','EN_ETUDE','LISTE_NOTIFIEE','VALIDE','ORDRE_EMIS','PAYE',
                             'MEDAILLES_REMISES','CEREMONIE_PLANIFIEE','CLOTURE') NULL,   -- NULL à la création
  statut_nouveau        ENUM('SOUMIS','APPROUVE','REJETE','EN_ETUDE','LISTE_NOTIFIEE','VALIDE','ORDRE_EMIS','PAYE',
                             'MEDAILLES_REMISES','CEREMONIE_PLANIFIEE','CLOTURE') NOT NULL,
  localisation_physique VARCHAR(150) NULL,                      -- localisation au moment du changement
  utilisateur_id        BIGINT UNSIGNED NULL,                   -- NULL = changement automatique (ex. échéance du délai)
  date_changement       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  commentaire           VARCHAR(255) NULL,
  PRIMARY KEY (id),
  KEY idx_hd_dossier (dossier_id, date_changement),
  KEY idx_hd_statut (statut_nouveau),
  KEY idx_hd_utilisateur (utilisateur_id),
  CONSTRAINT fk_hd_dossier     FOREIGN KEY (dossier_id)     REFERENCES dossier (id),
  CONSTRAINT fk_hd_utilisateur FOREIGN KEY (utilisateur_id) REFERENCES utilisateur (id)
) ENGINE=InnoDB COMMENT='Historique append-only du dossier : base de la page de suivi et des délais de traitement';

-- =====================================================================
-- 4. ÉCHANGES AUTOUR DU DOSSIER (avant document, qui y renvoie)
-- =====================================================================
CREATE TABLE demande_complement (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id       BIGINT UNSIGNED NOT NULL,                    -- n° 14
  recipiendaire_id BIGINT UNSIGNED NULL,                        -- n° 15 : vide = tout le dossier
  date_demande     DATETIME NOT NULL,
  objet            VARCHAR(500) NOT NULL,
  date_reponse     DATETIME NULL,
  PRIMARY KEY (id),
  KEY idx_dc_dossier (dossier_id),
  KEY idx_dc_recipiendaire (recipiendaire_id),
  CONSTRAINT fk_dc_dossier       FOREIGN KEY (dossier_id)       REFERENCES dossier (id),
  CONSTRAINT fk_dc_recipiendaire FOREIGN KEY (recipiendaire_id) REFERENCES recipiendaire (id)
) ENGINE=InnoDB;

CREATE TABLE recours (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id           BIGINT UNSIGNED NOT NULL,                -- n° 11 : 0..* par dossier
  document_numerise_id BIGINT UNSIGNED NULL,                    -- n° 30 : fichier du courrier de recours
  date_recours         DATETIME NOT NULL,
  motif                VARCHAR(1000) NOT NULL,
  decision             ENUM('ACCEPTE','REJETE') NULL,           -- vide = en attente
  date_decision        DATETIME NULL,
  justification        TEXT NULL,
  indications_decision TEXT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_recours_dn (document_numerise_id),
  KEY idx_recours_dossier (dossier_id),
  CONSTRAINT fk_recours_dossier FOREIGN KEY (dossier_id)           REFERENCES dossier (id),
  CONSTRAINT fk_recours_dn      FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id)
) ENGINE=InnoDB COMMENT='Contestation d''un rejet ou de la liste des validés';

CREATE TABLE relance (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id           BIGINT UNSIGNED NOT NULL,                -- n° 16
  date_relance         DATETIME NOT NULL,
  destinataire         ENUM('DR','DGT','MINISTRE') NOT NULL DEFAULT 'DR',
  statut               ENUM('EN_ATTENTE','ACCEPTEE','REFUSEE') NOT NULL DEFAULT 'EN_ATTENTE',
  indications_decision TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_relance_dossier (dossier_id),
  CONSTRAINT fk_relance_dossier FOREIGN KEY (dossier_id) REFERENCES dossier (id)
) ENGINE=InnoDB COMMENT='Relance après cérémonie pour les distinctions non distribuées';

-- =====================================================================
-- 5. DOCUMENTS ET PAIEMENT
-- =====================================================================
CREATE TABLE document (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id           BIGINT UNSIGNED NOT NULL,                -- n° 10 : 1..* côté dossier
  document_numerise_id BIGINT UNSIGNED NULL,                    -- n° 9
  recours_id           BIGINT UNSIGNED NULL,                    -- n° 17
  demande_complement_id BIGINT UNSIGNED NULL,                   -- n° 18
  relance_id           BIGINT UNSIGNED NULL,                    -- n° 19
  recipiendaire_id     BIGINT UNSIGNED NULL,                    -- pièce propre à un récipiendaire (ex. justificatif de mutilation)
  type                 VARCHAR(60)  NOT NULL,                   -- COURRIER_INITIATION, DTS, ACTE, ATTESTATION, JUSTIFICATIF_MUTILATION, AUTRE...
  libelle              VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_document_dn (document_numerise_id),
  KEY idx_document_dossier (dossier_id),
  KEY idx_document_recours (recours_id),
  KEY idx_document_dc (demande_complement_id),
  KEY idx_document_relance (relance_id),
  KEY idx_document_recipiendaire (recipiendaire_id),
  CONSTRAINT fk_document_dossier  FOREIGN KEY (dossier_id)            REFERENCES dossier (id),
  CONSTRAINT fk_document_recipiendaire FOREIGN KEY (recipiendaire_id) REFERENCES recipiendaire (id),
  CONSTRAINT fk_document_dn       FOREIGN KEY (document_numerise_id)  REFERENCES document_numerise (id),
  CONSTRAINT fk_document_recours  FOREIGN KEY (recours_id)            REFERENCES recours (id),
  CONSTRAINT fk_document_dc       FOREIGN KEY (demande_complement_id) REFERENCES demande_complement (id),
  CONSTRAINT fk_document_relance  FOREIGN KEY (relance_id)            REFERENCES relance (id),
  -- une pièce jointe n'est rattachée qu'à un seul objet d'échange
  CONSTRAINT ck_document_un_seul_lien CHECK (
    (recours_id IS NOT NULL) + (demande_complement_id IS NOT NULL) + (relance_id IS NOT NULL)
    + (recipiendaire_id IS NOT NULL) <= 1)
) ENGINE=InnoDB COMMENT='Pièce du dossier (acte, attestation, courrier, DTS...)';

CREATE TABLE ordre_de_recette (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id           BIGINT UNSIGNED NOT NULL,                -- n° 12 : 0..1 par dossier
  document_numerise_id BIGINT UNSIGNED NULL,                    -- n° 31
  numero               VARCHAR(50)  NOT NULL,
  date_emission        DATE         NOT NULL,
  montant_total        DECIMAL(14,2) NOT NULL,                  -- calculé sur les validés d'après tarif
  PRIMARY KEY (id),
  UNIQUE KEY uq_ordre_dossier (dossier_id),
  UNIQUE KEY uq_ordre_numero (numero),
  UNIQUE KEY uq_ordre_dn (document_numerise_id),
  CONSTRAINT fk_ordre_dossier FOREIGN KEY (dossier_id)           REFERENCES dossier (id),
  CONSTRAINT fk_ordre_dn      FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id)
) ENGINE=InnoDB COMMENT='Document qui dit combien payer (paiement au Trésor, hors application)';

CREATE TABLE quittance (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ordre_de_recette_id  BIGINT UNSIGNED NOT NULL,                -- n° 13 : 0..1 par ordre
  document_numerise_id BIGINT UNSIGNED NULL,                    -- n° 32
  numero               VARCHAR(50)  NOT NULL,
  date_emission        DATE         NOT NULL,
  montant_paye         DECIMAL(14,2) NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_quittance_ordre (ordre_de_recette_id),
  UNIQUE KEY uq_quittance_dn (document_numerise_id),
  CONSTRAINT fk_quittance_ordre FOREIGN KEY (ordre_de_recette_id)  REFERENCES ordre_de_recette (id),
  CONSTRAINT fk_quittance_dn    FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id)
) ENGINE=InnoDB COMMENT='Preuve de paiement (scan de la quittance du Trésor)';

-- =====================================================================
-- 6. REMISES, MÉDAILLES, CÉRÉMONIES, RETRAITS
-- =====================================================================
CREATE TABLE remise_medailles (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id        BIGINT UNSIGNED NOT NULL,                   -- n° 27
  demandeur_id      BIGINT UNSIGNED NOT NULL,                   -- n° 28
  quittance_id      BIGINT UNSIGNED NOT NULL,                   -- n° 29
  nom_retirant      VARCHAR(100) NOT NULL,
  prenom_retirant   VARCHAR(100) NOT NULL,
  qualite_retirant  VARCHAR(60)  NOT NULL,                      -- représentant du demandeur, employé, mandataire, autre
  piece_identite    VARCHAR(100) NULL,
  date_retrait      DATETIME     NOT NULL,
  observations      TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_remise_dossier (dossier_id),
  KEY idx_remise_demandeur (demandeur_id),
  KEY idx_remise_quittance (quittance_id),
  CONSTRAINT fk_remise_dossier   FOREIGN KEY (dossier_id)   REFERENCES dossier (id),
  CONSTRAINT fk_remise_demandeur FOREIGN KEY (demandeur_id) REFERENCES demandeur (id),
  CONSTRAINT fk_remise_quittance FOREIGN KEY (quittance_id) REFERENCES quittance (id)
) ENGINE=InnoDB COMMENT='Acte de remise des médailles contre quittance';

-- 3. DISTINCTIONS
CREATE TABLE medaille (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipiendaire_id  BIGINT UNSIGNED NOT NULL,                   -- n° 7 : 0..3 par récipiendaire
  remise_id         BIGINT UNSIGNED NULL,                       -- n° 26 : remise 0..1 par médaille
  metal             ENUM('OR','ARGENT','BRONZE') NOT NULL,
  date_attribution  DATE NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_medaille_recip_metal (recipiendaire_id, metal), -- jamais 2 fois le même métal pour un même récipiendaire
  KEY idx_medaille_remise (remise_id),
  CONSTRAINT fk_medaille_recipiendaire FOREIGN KEY (recipiendaire_id) REFERENCES recipiendaire (id),
  CONSTRAINT fk_medaille_remise        FOREIGN KEY (remise_id)        REFERENCES remise_medailles (id)
) ENGINE=InnoDB COMMENT='Médaille attribuée à un récipiendaire (un enregistrement par entreprise)';

CREATE TABLE diplome_du_travail (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  medaille_id       BIGINT UNSIGNED NOT NULL,                   -- n° 8 : 1 - 1
  nom_recipiendaire VARCHAR(220) NOT NULL,
  distinction       ENUM('OR','ARGENT','BRONZE') NOT NULL,
  entreprise        VARCHAR(200) NOT NULL,
  date_delivrance   DATE NOT NULL,                              -- date d'acceptation de la liste par le demandeur (version numérique disponible dès lors)
  annee             SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_diplome_medaille (medaille_id),
  CONSTRAINT fk_diplome_medaille FOREIGN KEY (medaille_id) REFERENCES medaille (id)
) ENGINE=InnoDB COMMENT='Diplôme généré par l''application ; non signé, sans fiche de fichier';

CREATE TABLE ceremonie (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  type             ENUM('OFFICIELLE','HORS_DELAI','RATTRAPAGE') NOT NULL,
  date_proposee    DATE NULL,
  lieu_propose     VARCHAR(200) NULL,
  date_confirmee   DATE NULL,
  lieu_confirme    VARCHAR(200) NULL,
  statut           ENUM('PROPOSEE','EN_NEGOCIATION','CONFIRMEE','TENUE','ANNULEE') NOT NULL DEFAULT 'PROPOSEE',
  PRIMARY KEY (id),
  KEY idx_ceremonie_statut (statut)
) ENGINE=InnoDB COMMENT='Cérémonie de remise ; proposition et confirmation séparées pour garder la négociation';

CREATE TABLE participation (                                    -- n-n Recipiendaire / Ceremonie
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipiendaire_id       BIGINT UNSIGNED NOT NULL,              -- n° 20
  ceremonie_id           BIGINT UNSIGNED NOT NULL,              -- n° 21
  present                TINYINT(1) NULL,                       -- vide tant que la cérémonie n'a pas eu lieu
  date_remise_effective  DATE NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_participation (recipiendaire_id, ceremonie_id),
  KEY idx_participation_ceremonie (ceremonie_id),
  CONSTRAINT fk_participation_recipiendaire FOREIGN KEY (recipiendaire_id) REFERENCES recipiendaire (id),
  CONSTRAINT fk_participation_ceremonie     FOREIGN KEY (ceremonie_id)     REFERENCES ceremonie (id)
) ENGINE=InnoDB;

CREATE TABLE document_delegation (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ceremonie_id         BIGINT UNSIGNED NOT NULL,                -- n° 22 : 0..1 par cérémonie
  document_numerise_id BIGINT UNSIGNED NULL,                    -- n° 33
  PRIMARY KEY (id),
  UNIQUE KEY uq_delegation_ceremonie (ceremonie_id),
  UNIQUE KEY uq_delegation_dn (document_numerise_id),
  CONSTRAINT fk_delegation_ceremonie FOREIGN KEY (ceremonie_id)         REFERENCES ceremonie (id),
  CONSTRAINT fk_delegation_dn        FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id)
) ENGINE=InnoDB COMMENT='Document généré listant la délégation d''un demandeur (signé)';

CREATE TABLE membre_delegation (
  id                       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  document_delegation_id   BIGINT UNSIGNED NOT NULL,            -- n° 23
  nom                      VARCHAR(150) NOT NULL,
  fonction                 VARCHAR(150) NULL,
  PRIMARY KEY (id),
  KEY idx_membre_delegation (document_delegation_id),
  CONSTRAINT fk_membre_delegation FOREIGN KEY (document_delegation_id) REFERENCES document_delegation (id)
) ENGINE=InnoDB;

CREATE TABLE retrait_sans_ceremonie (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipiendaire_id       BIGINT UNSIGNED NOT NULL,              -- n° 24
  compte_interne_id      BIGINT UNSIGNED NULL,                  -- n° 25 : régisseur qui vérifie (NULL tant que non vérifié)
  date_retrait           DATE NULL,
  justificatif_verifie   TINYINT(1) NULL,                       -- NULL = en attente, 1 = valide, 0 = invalide
  nom_retirant           VARCHAR(100) NOT NULL,
  prenom_retirant        VARCHAR(100) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_retrait_recipiendaire (recipiendaire_id),
  KEY idx_retrait_compte (compte_interne_id),
  CONSTRAINT fk_retrait_recipiendaire FOREIGN KEY (recipiendaire_id)  REFERENCES recipiendaire (id),
  CONSTRAINT fk_retrait_compte        FOREIGN KEY (compte_interne_id) REFERENCES compte_interne (id)
) ENGINE=InnoDB COMMENT='Retrait d''une médaille et d''un diplôme sans cérémonie';

-- =====================================================================
-- 7. STOCK ET ACHATS
-- =====================================================================
CREATE TABLE stock_distinction (
  type_distinction        ENUM('OR','ARGENT','BRONZE') NOT NULL,
  quantite_stock_actuel   INT NOT NULL DEFAULT 0,
  quantite_entree_total   INT NOT NULL DEFAULT 0,
  quantite_sortie_total   INT NOT NULL DEFAULT 0,
  date_derniere_mise_a_jour DATETIME NULL,
  PRIMARY KEY (type_distinction),
  CONSTRAINT ck_stock_positif CHECK (quantite_stock_actuel >= 0)
) ENGINE=InnoDB COMMENT='Une ligne par métal';

CREATE TABLE tarif (                                            -- même clé naturelle que le stock, sans liaison dessinée
  type_distinction      ENUM('OR','ARGENT','BRONZE','DIPLOME') NOT NULL,
  prix_vente            DECIMAL(12,2) NOT NULL,
  prix_achat_fournisseur DECIMAL(12,2) NULL,                    -- inconnu pour l'instant
  PRIMARY KEY (type_distinction)
) ENGINE=InnoDB;

CREATE TABLE fournisseur (
  id       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom      VARCHAR(200) NOT NULL,
  contact  VARCHAR(255) NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE budget_achat (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  campagne_id     BIGINT UNSIGNED NOT NULL,                     -- n° 36
  montant_alloue  DECIMAL(14,2) NOT NULL,
  PRIMARY KEY (id),
  KEY idx_budget_campagne (campagne_id),
  CONSTRAINT fk_budget_campagne FOREIGN KEY (campagne_id) REFERENCES campagne (id)
) ENGINE=InnoDB;

CREATE TABLE bon_commande (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  budget_achat_id       BIGINT UNSIGNED NULL,                   -- n° 37 : 0..1
  fournisseur_id        BIGINT UNSIGNED NOT NULL,               -- n° 39
  document_numerise_id  BIGINT UNSIGNED NULL,                   -- n° 41
  numero                VARCHAR(50) NOT NULL,
  date_commande         DATE NOT NULL,
  statut                ENUM('BROUILLON','PASSEE','PARTIELLEMENT_LIVREE','LIVREE','ANNULEE') NOT NULL DEFAULT 'BROUILLON',
  PRIMARY KEY (id),
  UNIQUE KEY uq_bc_numero (numero),
  UNIQUE KEY uq_bc_dn (document_numerise_id),
  KEY idx_bc_budget (budget_achat_id),
  KEY idx_bc_fournisseur (fournisseur_id),
  CONSTRAINT fk_bc_budget      FOREIGN KEY (budget_achat_id)      REFERENCES budget_achat (id),
  CONSTRAINT fk_bc_fournisseur FOREIGN KEY (fournisseur_id)       REFERENCES fournisseur (id),
  CONSTRAINT fk_bc_dn          FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id)
) ENGINE=InnoDB COMMENT='Chaîne d''approvisionnement : hypothèse à valider avec le régisseur';

CREATE TABLE ligne_commande (                                   -- identifiée par commande + métal
  bon_commande_id   BIGINT UNSIGNED NOT NULL,                   -- n° 38 : 1..*
  type_distinction  ENUM('OR','ARGENT','BRONZE') NOT NULL,
  quantite          INT NOT NULL,
  prix_negocie      DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (bon_commande_id, type_distinction),
  CONSTRAINT fk_ligne_bc FOREIGN KEY (bon_commande_id) REFERENCES bon_commande (id),
  CONSTRAINT ck_ligne_quantite CHECK (quantite > 0)
) ENGINE=InnoDB;

CREATE TABLE bon_livraison (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  bon_commande_id       BIGINT UNSIGNED NOT NULL,               -- n° 40 : 0..*
  document_numerise_id  BIGINT UNSIGNED NULL,                   -- n° 42
  numero                VARCHAR(50) NOT NULL,
  date_livraison        DATE NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_bl_numero (numero),
  UNIQUE KEY uq_bl_dn (document_numerise_id),
  KEY idx_bl_bc (bon_commande_id),
  CONSTRAINT fk_bl_bc FOREIGN KEY (bon_commande_id)      REFERENCES bon_commande (id),
  CONSTRAINT fk_bl_dn FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id)
) ENGINE=InnoDB;

CREATE TABLE mouvement_stock (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  type_distinction   ENUM('OR','ARGENT','BRONZE') NOT NULL,     -- n° 43
  bon_livraison_id   BIGINT UNSIGNED NULL,                      -- n° 44 : seules les entrées
  compte_interne_id  BIGINT UNSIGNED NULL,                      -- n° 45 : NULL si automatique
  sens               ENUM('ENTREE','SORTIE') NOT NULL,
  quantite           INT NOT NULL,
  date_mouvement     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  motif              VARCHAR(255) NULL,
  PRIMARY KEY (id),
  KEY idx_mvt_type (type_distinction),
  KEY idx_mvt_bl (bon_livraison_id),
  KEY idx_mvt_compte (compte_interne_id),
  CONSTRAINT fk_mvt_stock   FOREIGN KEY (type_distinction)  REFERENCES stock_distinction (type_distinction),
  CONSTRAINT fk_mvt_bl      FOREIGN KEY (bon_livraison_id)  REFERENCES bon_livraison (id),
  CONSTRAINT fk_mvt_compte  FOREIGN KEY (compte_interne_id) REFERENCES compte_interne (id),
  CONSTRAINT ck_mvt_quantite CHECK (quantite > 0)
) ENGINE=InnoDB COMMENT='Historique des entrées (livraisons) et sorties (remises)';

-- =====================================================================
-- 8. STATISTIQUES ET FONCTIONS TRANSVERSES
-- =====================================================================
CREATE TABLE statistique_campagne (
  id                          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  campagne_id                 BIGINT UNSIGNED NOT NULL,         -- n° 34 : 1 - 1
  nb_dossiers_soumis          INT NOT NULL DEFAULT 0,
  nb_dossiers_valides         INT NOT NULL DEFAULT 0,
  nb_recipiendaires_valides   INT NOT NULL DEFAULT 0,
  nb_medailles_or             INT NOT NULL DEFAULT 0,
  nb_medailles_argent         INT NOT NULL DEFAULT 0,
  nb_medailles_bronze         INT NOT NULL DEFAULT 0,
  nb_diplomes_remis           INT NOT NULL DEFAULT 0,
  montant_total_percu         DECIMAL(14,2) NOT NULL DEFAULT 0,
  nb_ceremonies_tenues        INT NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uq_stat_campagne (campagne_id),
  CONSTRAINT fk_stat_campagne FOREIGN KEY (campagne_id) REFERENCES campagne (id)
) ENGINE=InnoDB COMMENT='Compteurs en direct, mis à jour à chaque événement';

CREATE TABLE archive_statistique_campagne (
  id                          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  campagne_id                 BIGINT UNSIGNED NOT NULL,         -- n° 35 : 0..1
  nb_dossiers_soumis          INT NOT NULL,
  nb_dossiers_valides         INT NOT NULL,
  nb_recipiendaires_valides   INT NOT NULL,
  nb_medailles_or             INT NOT NULL,
  nb_medailles_argent         INT NOT NULL,
  nb_medailles_bronze         INT NOT NULL,
  nb_diplomes_remis           INT NOT NULL,
  montant_total_percu         DECIMAL(14,2) NOT NULL,
  nb_ceremonies_tenues        INT NOT NULL,
  repartitions                JSON NULL,                        -- cliché figé : sexe, nationalité, secteur, province, métal demandé/décerné
  date_archivage              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_archive_campagne (campagne_id),
  CONSTRAINT fk_archive_campagne FOREIGN KEY (campagne_id) REFERENCES campagne (id)
) ENGINE=InnoDB COMMENT='Cliché figé des compteurs à la clôture';

CREATE TABLE assistant_ia (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  nom_modele  VARCHAR(100) NOT NULL,
  version     VARCHAR(30)  NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

CREATE TABLE notification (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  utilisateur_id   BIGINT UNSIGNED NOT NULL,                    -- n° 46
  assistant_ia_id  BIGINT UNSIGNED NULL,                        -- n° 48
  objet            VARCHAR(200) NOT NULL,
  message          TEXT NOT NULL,
  date_envoi       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  est_lue          TINYINT(1) NOT NULL DEFAULT 0,
  envoyee_par_mail TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY idx_notif_utilisateur (utilisateur_id, est_lue),
  KEY idx_notif_assistant (assistant_ia_id),
  CONSTRAINT fk_notif_utilisateur FOREIGN KEY (utilisateur_id)  REFERENCES utilisateur (id),
  CONSTRAINT fk_notif_assistant   FOREIGN KEY (assistant_ia_id) REFERENCES assistant_ia (id)
) ENGINE=InnoDB COMMENT='Une notification à chaque transmission et événement du parcours';

CREATE TABLE journal_activite (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  utilisateur_id   BIGINT UNSIGNED NULL,                        -- n° 47 : NULL = action de l'assistant
  assistant_ia_id  BIGINT UNSIGNED NULL,                        -- n° 49
  action           VARCHAR(150) NOT NULL,
  date_action      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  details          TEXT NULL,
  PRIMARY KEY (id),
  KEY idx_ja_utilisateur (utilisateur_id),
  KEY idx_ja_assistant (assistant_ia_id),
  KEY idx_ja_date (date_action),
  CONSTRAINT fk_ja_utilisateur FOREIGN KEY (utilisateur_id)  REFERENCES utilisateur (id),
  CONSTRAINT fk_ja_assistant   FOREIGN KEY (assistant_ia_id) REFERENCES assistant_ia (id)
) ENGINE=InnoDB COMMENT='Qui a fait quoi et quand (inclut chaque accès à un fichier)';

-- =====================================================================
-- 9. TRANSMISSION, SIGNATURE, VISAS
-- =====================================================================
CREATE TABLE transmission (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  document_numerise_id  BIGINT UNSIGNED NOT NULL,               -- n° 50
  dossier_id            BIGINT UNSIGNED NULL,                   -- n° 51
  expediteur_id         BIGINT UNSIGNED NOT NULL,               -- n° 52
  destinataire_id       BIGINT UNSIGNED NULL,                   -- n° 53 : NULL tant qu'une personne ne l'a pas pris en charge
  role_destinataire     ENUM('SECRETARIAT','MINISTRE','DGT','DR','SERVICE_DISTINCTIONS','REGISSEUR','ADMINISTRATEUR','DEMANDEUR') NULL,
  date_envoi            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_reception        DATETIME NULL,
  date_lecture          DATETIME NULL,
  statut                ENUM('ENVOYEE','RECUE','LUE') NOT NULL DEFAULT 'ENVOYEE',
  motif                 VARCHAR(255) NULL,                      -- pour décision, information, signature...
  PRIMARY KEY (id),
  KEY idx_tr_document (document_numerise_id),
  KEY idx_tr_dossier (dossier_id),
  KEY idx_tr_expediteur (expediteur_id),
  KEY idx_tr_destinataire (destinataire_id, statut),
  CONSTRAINT fk_tr_document     FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id),
  CONSTRAINT fk_tr_dossier      FOREIGN KEY (dossier_id)           REFERENCES dossier (id),
  CONSTRAINT fk_tr_expediteur   FOREIGN KEY (expediteur_id)        REFERENCES utilisateur (id),
  CONSTRAINT fk_tr_destinataire FOREIGN KEY (destinataire_id)      REFERENCES utilisateur (id),
  CONSTRAINT ck_tr_cible CHECK (destinataire_id IS NOT NULL OR role_destinataire IS NOT NULL)
) ENGINE=InnoDB COMMENT='Suivi du trajet d''un document : le fichier ne bouge pas, l''accès circule';

CREATE TABLE signature (
  id                         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  utilisateur_id             BIGINT UNSIGNED NOT NULL,          -- n° 57 : titulaire
  chemin_fichier             VARCHAR(255) NOT NULL,
  nom_fichier_origine        VARCHAR(255) NOT NULL,
  mime_type                  VARCHAR(100) NOT NULL,
  empreinte_fichier          CHAR(64)     NOT NULL,
  statut                     ENUM('EN_ATTENTE_VALIDATION','ACTIVE','DESACTIVEE') NOT NULL DEFAULT 'EN_ATTENTE_VALIDATION',
  code_hash_activation       VARCHAR(255) NULL,                 -- seul le hash du code est gardé
  date_expiration_activation DATETIME     NULL,
  nb_tentatives_activation   TINYINT UNSIGNED NOT NULL DEFAULT 0,
  date_creation              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_activation            DATETIME     NULL,
  date_desactivation         DATETIME     NULL,
  motif_desactivation        VARCHAR(255) NULL,
  -- un seul profil ACTIVE par personne (colonne générée + unicité)
  actif_pour_utilisateur_id  BIGINT UNSIGNED AS (IF(statut = 'ACTIVE', utilisateur_id, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_signature_un_actif (actif_pour_utilisateur_id),
  KEY idx_signature_utilisateur (utilisateur_id),
  CONSTRAINT fk_signature_utilisateur FOREIGN KEY (utilisateur_id) REFERENCES utilisateur (id)
) ENGINE=InnoDB COMMENT='Image de signature d''une personne ; on désactive, on ne supprime jamais';

CREATE TABLE signature_apposee (
  id                        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  document_numerise_id      BIGINT UNSIGNED NOT NULL,           -- n° 54 : 0..1 signature par document
  signature_id              BIGINT UNSIGNED NOT NULL,           -- n° 55
  utilisateur_id            BIGINT UNSIGNED NOT NULL,           -- n° 56 : signataire (copie figée)
  code_hash                 VARCHAR(255) NULL,
  date_expiration_code      DATETIME     NULL,
  nb_tentatives             TINYINT UNSIGNED NOT NULL DEFAULT 0,
  date_validation_code      DATETIME     NULL,
  hash_contenu_avant_numero CHAR(64)     NULL,                  -- hash du contenu sans le numéro ajouté après
  adresse_ip                VARCHAR(45)  NULL,
  user_agent                VARCHAR(500) NULL,
  date_signature            DATETIME     NULL,
  statut                    ENUM('EN_ATTENTE_OTP','SIGNE_VISUELLEMENT','SCELLE') NOT NULL DEFAULT 'EN_ATTENTE_OTP',
  date_scellement           DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sa_document (document_numerise_id),
  KEY idx_sa_signature (signature_id),
  KEY idx_sa_utilisateur (utilisateur_id),
  CONSTRAINT fk_sa_document    FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id),
  CONSTRAINT fk_sa_signature   FOREIGN KEY (signature_id)         REFERENCES signature (id),
  CONSTRAINT fk_sa_utilisateur FOREIGN KEY (utilisateur_id)       REFERENCES utilisateur (id)
) ENGINE=InnoDB COMMENT='L''acte de signer : preuve (code, IP, date) ; écrit une fois';

CREATE TABLE visa (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  utilisateur_id      BIGINT UNSIGNED NOT NULL,                 -- n° 61 : titulaire
  chemin_fichier      VARCHAR(255) NOT NULL,
  nom_fichier_origine VARCHAR(255) NOT NULL,
  mime_type           VARCHAR(100) NOT NULL,
  empreinte_fichier   CHAR(64)     NOT NULL,
  statut              ENUM('ACTIVE','DESACTIVEE') NOT NULL DEFAULT 'ACTIVE',
  date_creation       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_desactivation  DATETIME     NULL,
  PRIMARY KEY (id),
  KEY idx_visa_utilisateur (utilisateur_id),
  CONSTRAINT fk_visa_utilisateur FOREIGN KEY (utilisateur_id) REFERENCES utilisateur (id)
) ENGINE=InnoDB COMMENT='Paraphe d''un agent';

CREATE TABLE visa_apposee (                                     -- n-n Document / Visa
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  document_numerise_id  BIGINT UNSIGNED NOT NULL,               -- n° 58
  visa_id               BIGINT UNSIGNED NOT NULL,               -- n° 59
  utilisateur_id        BIGINT UNSIGNED NOT NULL,               -- n° 60 : visé par (copie figée)
  ordre_visa            SMALLINT UNSIGNED NOT NULL,
  date_visa             DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_va_ordre (document_numerise_id, ordre_visa),
  KEY idx_va_visa (visa_id),
  KEY idx_va_utilisateur (utilisateur_id),
  CONSTRAINT fk_va_document    FOREIGN KEY (document_numerise_id) REFERENCES document_numerise (id),
  CONSTRAINT fk_va_visa        FOREIGN KEY (visa_id)              REFERENCES visa (id),
  CONSTRAINT fk_va_utilisateur FOREIGN KEY (utilisateur_id)       REFERENCES utilisateur (id)
) ENGINE=InnoDB;

CREATE TABLE journal_signature (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  utilisateur_id        BIGINT UNSIGNED NOT NULL,               -- n° 65 : auteur
  signature_id          BIGINT UNSIGNED NULL,                   -- n° 66
  signature_apposee_id  BIGINT UNSIGNED NULL,                   -- n° 67
  type_evenement        VARCHAR(40)  NOT NULL,                  -- CREATION, ENVOI_CODE, ACTIVATION, DESACTIVATION, APPOSITION, NUMEROTATION, SCELLEMENT, CONSULTATION...
  adresse_ip            VARCHAR(45)  NULL,
  user_agent            VARCHAR(500) NULL,
  date_evenement        DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),   -- heure du serveur
  details               TEXT NULL,
  hash_precedent        CHAR(64)     NULL,                      -- NULL pour la toute première ligne
  hash_courant          CHAR(64)     NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_js_hash (hash_courant),
  KEY idx_js_utilisateur (utilisateur_id),
  KEY idx_js_signature (signature_id),
  KEY idx_js_apposee (signature_apposee_id),
  CONSTRAINT fk_js_utilisateur FOREIGN KEY (utilisateur_id)       REFERENCES utilisateur (id),
  CONSTRAINT fk_js_signature   FOREIGN KEY (signature_id)         REFERENCES signature (id),
  CONSTRAINT fk_js_apposee     FOREIGN KEY (signature_apposee_id) REFERENCES signature_apposee (id)
) ENGINE=InnoDB COMMENT='Journal de preuve : append-only et chaîné (hash_precedent -> hash_courant)';

-- =====================================================================
-- RÈGLES QUE LE DESSIN NE PEUT PAS EXPRIMER : DÉCLENCHEURS
-- =====================================================================
DELIMITER $$

-- Journal de signature : on ajoute, on ne modifie ni ne supprime jamais
CREATE TRIGGER trg_js_no_update BEFORE UPDATE ON journal_signature
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'journal_signature est append-only : modification interdite';
END$$

CREATE TRIGGER trg_js_no_delete BEFORE DELETE ON journal_signature
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'journal_signature est append-only : suppression interdite';
END$$

-- Historique du dossier : on ajoute, on ne modifie ni ne supprime jamais
CREATE TRIGGER trg_hd_no_update BEFORE UPDATE ON historique_dossier
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'historique_dossier est append-only : modification interdite';
END$$

CREATE TRIGGER trg_hd_no_delete BEFORE DELETE ON historique_dossier
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'historique_dossier est append-only : suppression interdite';
END$$

-- Document scellé : le fichier ne peut plus être remplacé (une correction = nouveau document)
CREATE TRIGGER trg_dn_verrou BEFORE UPDATE ON document_numerise
FOR EACH ROW BEGIN
  IF OLD.statut_signature = 'SIGNE_SCELLE'
     AND (NEW.chemin_fichier <> OLD.chemin_fichier OR NEW.nom_fichier <> OLD.nom_fichier) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'document scelle : remplacement du fichier interdit';
  END IF;
END$$

-- Anti-doublon : même personne (CNI), même demandeur, même métal -> refusé
-- (chez un autre demandeur, c'est autorisé)
CREATE TRIGGER trg_medaille_anti_doublon BEFORE INSERT ON medaille
FOR EACH ROW BEGIN
  DECLARE v_cni VARCHAR(30);
  DECLARE v_demandeur BIGINT UNSIGNED;
  DECLARE v_nb INT;
  SELECT r.numero_cni, d.demandeur_id INTO v_cni, v_demandeur
    FROM recipiendaire r JOIN dossier d ON d.id = r.dossier_id
   WHERE r.id = NEW.recipiendaire_id;
  SELECT COUNT(*) INTO v_nb
    FROM medaille m
    JOIN recipiendaire r2 ON r2.id = m.recipiendaire_id
    JOIN dossier d2       ON d2.id = r2.dossier_id
   WHERE r2.numero_cni = v_cni AND d2.demandeur_id = v_demandeur AND m.metal = NEW.metal;
  IF v_nb > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'doublon : cette personne a deja cette medaille chez ce demandeur';
  END IF;
END$$

DELIMITER ;

-- =====================================================================
-- VUES STATISTIQUES (alimentent les graphiques ; calculées à la lecture)
--
-- Pourquoi des vues plutôt que des compteurs ? Les « nombres distincts »
-- (entreprises décorées, personnes décorées) ne se tiennent pas à jour par
-- simples incréments sans dérive. Une vue relit toujours les vraies données :
-- elle ne peut pas se désynchroniser. Les compteurs statistique_campagne
-- restent pour les indicateurs rapides ; archive_statistique_campagne.repartitions
-- fige le résultat de ces vues à la clôture d'une campagne.
--
-- Définitions (à respecter dans le back) :
--   - « décoré » = médaille attribuée (dossier au moins VALIDE) ; la colonne
--     remise_au_demandeur indique si la médaille est déjà sortie du Ministère.
--   - « année » = année de la campagne du dossier.
--   - une personne = un numero_cni distinct (une personne décorée par deux
--     demandeurs la même année compte une seule fois dans les graphiques de personnes).
--   - ancienneté = année de la campagne - annee_entree_service.
-- =====================================================================

-- Base commune : une ligne par médaille attribuée, avec toutes les dimensions
CREATE OR REPLACE VIEW v_decoration AS
SELECT
  m.id                      AS medaille_id,
  m.metal                   AS metal,
  (m.remise_id IS NOT NULL) AS remise_au_demandeur,
  c.annee                   AS annee,
  doss.id                   AS dossier_id,
  dm.id                     AS demandeur_id,
  dm.nom                    AS demandeur_nom,
  dm.type_demandeur         AS type_demandeur,
  dm.secteur_activite_id    AS secteur_activite_id,
  sa.libelle                AS secteur_activite,
  dm.province_id            AS province_id,
  pv.nom                    AS province,
  r.id                      AS recipiendaire_id,
  r.numero_cni              AS numero_cni,
  r.sexe                    AS sexe,
  r.nationalite_id          AS nationalite_id,
  na.libelle                AS nationalite,
  (c.annee - r.annee_entree_service) AS anciennete,
  (r.taux_mutilation IS NOT NULL AND r.taux_mutilation >= 50) AS est_mutile,
  (r.date_deces IS NOT NULL) AS est_posthume
FROM medaille m
JOIN recipiendaire r  ON r.id = m.recipiendaire_id
JOIN dossier doss     ON doss.id = r.dossier_id
JOIN campagne c       ON c.id = doss.campagne_id
JOIN demandeur dm     ON dm.id = doss.demandeur_id
JOIN nationalite na   ON na.id = r.nationalite_id
LEFT JOIN secteur_activite sa ON sa.id = dm.secteur_activite_id
LEFT JOIN province pv         ON pv.id = dm.province_id;

-- 1. Nombre d'entreprises (et de personnes, de médailles) décorées au fil des années
CREATE OR REPLACE VIEW v_stat_decorations_annee AS
SELECT
  annee,
  COUNT(DISTINCT demandeur_id)                                                  AS nb_demandeurs_decores,
  COUNT(DISTINCT CASE WHEN type_demandeur = 'ENTREPRISE' THEN demandeur_id END) AS nb_entreprises_decorees,
  COUNT(DISTINCT numero_cni)                                                    AS nb_personnes_decorees,
  COUNT(*)                                                                      AS nb_medailles,
  SUM(metal = 'OR')                                                             AS nb_or,
  SUM(metal = 'ARGENT')                                                         AS nb_argent,
  SUM(metal = 'BRONZE')                                                         AS nb_bronze
FROM v_decoration
GROUP BY annee;

-- 2. Pourcentage d'hommes et de femmes décorés (par année)
CREATE OR REPLACE VIEW v_stat_sexe_annee AS
SELECT
  annee,
  sexe,
  COUNT(DISTINCT numero_cni) AS nb_personnes,
  ROUND(100 * COUNT(DISTINCT numero_cni) / SUM(COUNT(DISTINCT numero_cni)) OVER (PARTITION BY annee), 1) AS pourcentage
FROM v_decoration
GROUP BY annee, sexe;

-- 3. Médaille la plus demandée / la plus décernée, et taux d'attribution
CREATE OR REPLACE VIEW v_stat_metal_annee AS
SELECT
  t.annee,
  t.metal,
  SUM(t.nb_demandees) AS nb_demandees,
  SUM(t.nb_decernees) AS nb_decernees,
  ROUND(100 * SUM(t.nb_decernees) / NULLIF(SUM(t.nb_demandees), 0), 1) AS taux_attribution
FROM (
  SELECT c.annee AS annee, dd.metal AS metal, 1 AS nb_demandees, 0 AS nb_decernees
    FROM distinction_demandee dd
    JOIN recipiendaire r ON r.id = dd.recipiendaire_id
    JOIN dossier d       ON d.id = r.dossier_id
    JOIN campagne c      ON c.id = d.campagne_id
  UNION ALL
  SELECT annee, metal, 0, 1 FROM v_decoration
) t
GROUP BY t.annee, t.metal;

-- 4. Secteur d'activité qui décore le plus (entreprises seulement)
CREATE OR REPLACE VIEW v_stat_secteur_annee AS
SELECT
  annee,
  COALESCE(secteur_activite, 'Non renseigné') AS secteur_activite,
  COUNT(DISTINCT demandeur_id)                AS nb_entreprises,
  COUNT(DISTINCT numero_cni)                  AS nb_personnes,
  COUNT(*)                                    AS nb_medailles
FROM v_decoration
WHERE type_demandeur = 'ENTREPRISE'
GROUP BY annee, secteur_activite_id, secteur_activite;

-- 5. Nationalité la plus décorée
CREATE OR REPLACE VIEW v_stat_nationalite_annee AS
SELECT
  annee,
  nationalite,
  COUNT(DISTINCT numero_cni) AS nb_personnes,
  ROUND(100 * COUNT(DISTINCT numero_cni) / SUM(COUNT(DISTINCT numero_cni)) OVER (PARTITION BY annee), 1) AS pourcentage
FROM v_decoration
GROUP BY annee, nationalite_id, nationalite;

-- 6. Répartition géographique (province du siège du demandeur)
CREATE OR REPLACE VIEW v_stat_province_annee AS
SELECT
  annee,
  COALESCE(province, 'Non renseignée') AS province,
  COUNT(DISTINCT demandeur_id)         AS nb_demandeurs,
  COUNT(DISTINCT numero_cni)           AS nb_personnes,
  COUNT(*)                             AS nb_medailles
FROM v_decoration
GROUP BY annee, province_id, province;

-- 7. Répartition par tranche d'ancienneté (tranches fixes, pour le graphique seulement)
CREATE OR REPLACE VIEW v_stat_anciennete_annee AS
SELECT
  x.annee,
  x.tranche,
  COUNT(DISTINCT x.numero_cni) AS nb_personnes
FROM (
  SELECT annee, numero_cni,
         CASE WHEN anciennete < 10 THEN 'MOINS_DE_10'
              WHEN anciennete < 20 THEN '10_A_19'
              WHEN anciennete < 30 THEN '20_A_29'
              ELSE '30_ET_PLUS' END AS tranche
  FROM v_decoration
) x
GROUP BY x.annee, x.tranche;

-- 8. Mutilés du travail (taux >= 50) et remises posthumes décorés
CREATE OR REPLACE VIEW v_stat_mutiles_posthumes_annee AS
SELECT
  annee,
  COUNT(DISTINCT CASE WHEN est_mutile = 1    THEN numero_cni END) AS nb_mutiles_decores,
  COUNT(DISTINCT CASE WHEN est_posthume = 1  THEN numero_cni END) AS nb_posthumes_decores
FROM v_decoration
GROUP BY annee;

-- 9. Demandeurs qui décorent le plus (classement : trier côté requête)
CREATE OR REPLACE VIEW v_stat_top_demandeurs AS
SELECT
  demandeur_id,
  demandeur_nom,
  type_demandeur,
  COUNT(*)                   AS nb_medailles,
  COUNT(DISTINCT numero_cni) AS nb_personnes,
  COUNT(DISTINCT annee)      AS nb_annees,
  MAX(annee)                 AS derniere_annee
FROM v_decoration
GROUP BY demandeur_id, demandeur_nom, type_demandeur;

-- 10. Dossiers déposés / rejetés et récipiendaires validés / refusés
CREATE OR REPLACE VIEW v_stat_validation_annee AS
SELECT
  c.annee                                                     AS annee,
  COUNT(DISTINCT d.id)                                        AS nb_dossiers,
  COUNT(DISTINCT CASE WHEN d.statut = 'REJETE' THEN d.id END) AS nb_dossiers_rejetes,
  COUNT(r.id)                                                 AS nb_recipiendaires,
  COALESCE(SUM(r.statut_validation = 'VALIDE'), 0)            AS nb_recipiendaires_valides,
  COALESCE(SUM(r.statut_validation = 'REFUSE'), 0)            AS nb_recipiendaires_refuses
FROM campagne c
JOIN dossier d            ON d.campagne_id = c.id
LEFT JOIN recipiendaire r ON r.dossier_id = d.id
GROUP BY c.annee;

-- 11. Délai moyen de traitement (dépôt -> première validation), d'après l'historique
CREATE OR REPLACE VIEW v_stat_delai_traitement_annee AS
SELECT
  c.annee                                              AS annee,
  COUNT(*)                                             AS nb_dossiers_valides,
  ROUND(AVG(DATEDIFF(h.date_validation, d.date_depot)), 1) AS delai_moyen_jours
FROM dossier d
JOIN campagne c ON c.id = d.campagne_id
JOIN (
  SELECT dossier_id, MIN(date_changement) AS date_validation
    FROM historique_dossier
   WHERE statut_nouveau = 'VALIDE'
   GROUP BY dossier_id
) h ON h.dossier_id = d.id
GROUP BY c.annee;

-- =====================================================================
-- DONNÉES DE RÉFÉRENCE
-- =====================================================================
INSERT INTO stock_distinction (type_distinction) VALUES ('OR'), ('ARGENT'), ('BRONZE');

INSERT INTO tarif (type_distinction, prix_vente) VALUES
  ('OR', 20000), ('ARGENT', 15000), ('BRONZE', 13000), ('DIPLOME', 3000);

INSERT INTO assistant_ia (nom_modele, version) VALUES ('Assistant distinctions', '0.1');

-- Provinces du Gabon (les 9 provinces)
INSERT INTO province (nom) VALUES
  ('Estuaire'), ('Haut-Ogooué'), ('Moyen-Ogooué'), ('Ngounié'), ('Nyanga'),
  ('Ogooué-Ivindo'), ('Ogooué-Lolo'), ('Ogooué-Maritime'), ('Woleu-Ntem');

-- Secteurs d'activité : liste de DÉPART, à remplacer par la nomenclature du Ministère
INSERT INTO secteur_activite (libelle) VALUES
  ('Pétrole et gaz'), ('Mines'), ('Bois et forêt'), ('Agro-industrie'),
  ('Banques et assurances'), ('Commerce et distribution'), ('BTP et construction'),
  ('Transport et logistique'), ('Énergie et eau'), ('Télécommunications'),
  ('Santé'), ('Éducation'), ('Autres secteurs');

-- Nationalités : le seeder du back charge la liste complète (ISO 3166) ; une ligne d'amorce ici
INSERT INTO nationalite (code_iso, pays, libelle) VALUES ('GA', 'Gabon', 'Gabonaise');

-- =====================================================================
-- RÈGLES RESTANT À FAIRE RESPECTER PAR L'APPLICATION
--  - Dépôt : courrier d'initiation + au moins un récipiendaire.
--  - document_numerise appartient à un seul objet (document, recours, ordre,
--    quittance, délégation, bon de commande ou de livraison).
--  - Ancienneté (en années) : Bronze dès 10 ans, Argent dès 20, Or dès 30 ;
--    verdict INFORMATIF (jamais bloquant) : l'inspecteur / le chef de service apprécie.
--  - taux_mutilation renseigné -> au moins un document JUSTIFICATIF_MUTILATION
--    rattaché au récipiendaire (document.recipiendaire_id) : règle applicative.
--  - Au moins un métal dans distinction_demandee par récipiendaire.
--  - Les médailles sont créées au passage du dossier à VALIDE (pas avant).
--   - Ne JAMAIS compter sur la valeur par défaut d'un ENUM NOT NULL (elle prend la
--     1re valeur : role, type_demandeur, metal...). Le back renseigne toujours ces
--     champs explicitement (FormRequest « required »). Exception assumée :
--     destinataire_initial DEFAULT 'DR' (N13) — le back peut omettre le champ.
--  - Chaque changement de statut écrit une ligne dans historique_dossier.
--  - Aucun délai de contestation : le dossier reste LISTE_NOTIFIEE jusqu'à l'acceptation du demandeur.
--  - Seuls INSPECTEUR et CHEF_SERVICE valident/refusent ; AGENT saisit et rédige (bloc 2).
--  - Saisie pour un demandeur reconnu : SECRETARIAT, AGENT ou CHEF_SERVICE (N14).
--  - Un profil signature ACTIVE à la fois (garanti ici par uq_signature_un_actif).
--  - Calcul de hash_courant de journal_signature (hash de la ligne + hash_precedent).
--  - Stock : une SORTIE à chaque remise de médailles ; mise à jour des compteurs.
-- =====================================================================
