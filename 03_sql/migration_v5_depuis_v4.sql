-- =====================================================================
--  MÉDITRA — Migration SQL v4 -> v5
--  Base de départ : distinctions_nationales_v4_user.sql (47 tables, 12 vues, 6 déclencheurs)
--  Cible : MySQL 8.0+ (InnoDB, utf8mb4). Testée aussi sur MariaDB 10.11.
--  À exécuter en UNE fois, dans l'ordre. Idempotence non prévue (migration unique).
--
--  Changements v5 :
--   V1  Rôle INSPECTEUR supprimé (postes : AGENT, CHEF_SERVICE).
--   V2  Dépôt physique saisi par le secrétariat : demandeur sans compte, mode de dépôt, reçu.
--   V3  Représentant (demandeur et dossier, copie figée).
--   V4  Agent prépare / Chef décide : avis de l'agent, décision du chef, compléments en brouillon.
--   V5  Délégation rédigée par le DR seul : versions, rang et métal des membres.
--   V6  Confirmation unique du demandeur (liste + exemple d'ordre), puis ordre émis par le CHEF seul.
--   V7  Quittance saisissable par le régisseur ; remise partielle (payées / reçues) ; mouvements de stock saisissables.
--   V8  Bilan de cérémonie, participation « décoré », archivage du dossier.
--   V9  Propositions de cérémonie du demandeur (le Service confirme ou refuse).
--   V10 Brouillon de dossier côté serveur.
--  Règle ENUM (RG-ARCH-11) : les nouveaux ENUM obligatoires sont NULL + CHECK « IS NOT NULL »,
--  jamais NOT NULL DEFAULT, pour qu'un oubli ne prenne pas la 1re valeur en silence.
-- =====================================================================
USE distinctions_nationales;

-- ---------------------------------------------------------------------
-- V1. Suppression du poste INSPECTEUR
--     Les inspecteurs existants deviennent AGENT (à revoir à la main : le chef peut les promouvoir).
-- ---------------------------------------------------------------------
UPDATE compte_interne SET poste_service = 'AGENT' WHERE poste_service = 'INSPECTEUR';
ALTER TABLE compte_interne
  MODIFY poste_service ENUM('AGENT','CHEF_SERVICE') NULL;

-- ---------------------------------------------------------------------
-- V2 + V3. Demandeur : sans compte (saisie interne), représentant
-- ---------------------------------------------------------------------
ALTER TABLE demandeur
  MODIFY utilisateur_id BIGINT UNSIGNED NULL,
  ADD COLUMN origine_creation ENUM('INSCRIPTION','SAISIE_INTERNE') NULL AFTER utilisateur_id,
  ADD COLUMN cree_par_id BIGINT UNSIGNED NULL AFTER origine_creation,
  ADD COLUMN email_contact VARCHAR(190) NULL,
  ADD COLUMN representant_nom       VARCHAR(100) NULL,
  ADD COLUMN representant_prenom    VARCHAR(100) NULL,
  ADD COLUMN representant_fonction  VARCHAR(150) NULL,
  ADD COLUMN representant_telephone VARCHAR(40)  NULL,
  ADD COLUMN representant_email     VARCHAR(190) NULL,
  ADD KEY idx_demandeur_cree_par (cree_par_id),
  ADD CONSTRAINT fk_demandeur_cree_par FOREIGN KEY (cree_par_id) REFERENCES compte_interne (id);
UPDATE demandeur SET origine_creation = 'INSCRIPTION' WHERE origine_creation IS NULL;
ALTER TABLE demandeur
  ADD CONSTRAINT ck_demandeur_origine CHECK (
    origine_creation IS NOT NULL AND (
      (origine_creation = 'INSCRIPTION'    AND utilisateur_id IS NOT NULL AND cree_par_id IS NULL)
   OR (origine_creation = 'SAISIE_INTERNE' AND cree_par_id IS NOT NULL)));
-- Un demandeur de saisie interne n'a pas de compte (utilisateur_id NULL) tant qu'il n'est pas invité à en créer un.
-- UNIQUE(utilisateur_id) reste valable : plusieurs NULL autorisés.

-- ---------------------------------------------------------------------
-- V2, V3, V6, V8. Dossier
-- ---------------------------------------------------------------------
ALTER TABLE dossier
  MODIFY statut ENUM('SOUMIS','APPROUVE','REJETE','EN_ETUDE','LISTE_NOTIFIEE','VALIDE','ORDRE_EMIS','PAYE',
                     'MEDAILLES_REMISES','CEREMONIE_PLANIFIEE','CLOTURE','ARCHIVE') NOT NULL DEFAULT 'SOUMIS',
  ADD COLUMN mode_depot ENUM('EN_LIGNE','PHYSIQUE') NULL,
  ADD COLUMN date_depot_physique DATE NULL,                 -- date figurant sur le reçu papier
  ADD COLUMN reference_recepisse VARCHAR(60) NULL,          -- n° du récépissé / du courrier reçu
  ADD COLUMN representant_nom       VARCHAR(100) NULL,      -- copie figée au dépôt
  ADD COLUMN representant_prenom    VARCHAR(100) NULL,
  ADD COLUMN representant_fonction  VARCHAR(150) NULL,
  ADD COLUMN representant_telephone VARCHAR(40)  NULL,
  ADD COLUMN representant_email     VARCHAR(190) NULL,
  ADD COLUMN apercu_ordre_montant DECIMAL(14,2) NULL,       -- exemple d'ordre envoyé au demandeur avec la liste (tarifs figés à la notification)
  ADD COLUMN apercu_ordre_detail  JSON NULL,                -- détail par métal : quantité, prix, diplômes
  ADD COLUMN date_apercu_ordre    DATETIME NULL,
  ADD COLUMN confirmation_mode ENUM('EN_LIGNE','PAR_AGENT') NULL,   -- comment la confirmation du demandeur a été obtenue
  ADD COLUMN confirmation_saisie_par_id BIGINT UNSIGNED NULL,        -- agent qui a enregistré la confirmation papier
  ADD COLUMN document_confirmation_id   BIGINT UNSIGNED NULL,        -- scan de la confirmation signée (obligatoire si PAR_AGENT)
  ADD COLUMN date_archivage DATETIME NULL,
  ADD COLUMN archive_par_id BIGINT UNSIGNED NULL,
  ADD KEY idx_dossier_conf_par (confirmation_saisie_par_id),
  ADD KEY idx_dossier_conf_doc (document_confirmation_id),
  ADD KEY idx_dossier_archive_par (archive_par_id),
  ADD CONSTRAINT fk_dossier_conf_par  FOREIGN KEY (confirmation_saisie_par_id) REFERENCES compte_interne (id),
  ADD CONSTRAINT fk_dossier_conf_doc  FOREIGN KEY (document_confirmation_id)   REFERENCES document_numerise (id),
  ADD CONSTRAINT fk_dossier_archive_par FOREIGN KEY (archive_par_id)           REFERENCES compte_interne (id);
UPDATE dossier
   SET mode_depot = IF(saisi_par_id IS NULL, 'EN_LIGNE', 'PHYSIQUE'),
       date_depot_physique = IF(saisi_par_id IS NULL, NULL, DATE(date_depot))
 WHERE mode_depot IS NULL;
ALTER TABLE dossier
  ADD CONSTRAINT ck_dossier_depot CHECK (
    mode_depot IS NOT NULL
    AND (mode_depot = 'EN_LIGNE' OR (date_depot_physique IS NOT NULL AND saisi_par_id IS NOT NULL))),
  ADD CONSTRAINT ck_dossier_confirmation CHECK (
    confirmation_mode IS NULL OR confirmation_mode = 'EN_LIGNE'
    OR (confirmation_saisie_par_id IS NOT NULL AND document_confirmation_id IS NOT NULL)),
  ADD CONSTRAINT ck_dossier_archive CHECK (
    statut <> 'ARCHIVE' OR (date_archivage IS NOT NULL AND archive_par_id IS NOT NULL));

ALTER TABLE historique_dossier
  MODIFY statut_ancien ENUM('SOUMIS','APPROUVE','REJETE','EN_ETUDE','LISTE_NOTIFIEE','VALIDE','ORDRE_EMIS','PAYE',
                            'MEDAILLES_REMISES','CEREMONIE_PLANIFIEE','CLOTURE','ARCHIVE') NULL,
  MODIFY statut_nouveau ENUM('SOUMIS','APPROUVE','REJETE','EN_ETUDE','LISTE_NOTIFIEE','VALIDE','ORDRE_EMIS','PAYE',
                             'MEDAILLES_REMISES','CEREMONIE_PLANIFIEE','CLOTURE','ARCHIVE') NOT NULL;

-- ---------------------------------------------------------------------
-- V4. Agent prépare / Chef décide
-- ---------------------------------------------------------------------
ALTER TABLE recipiendaire
  ADD COLUMN avis_agent ENUM('FAVORABLE','DEFAVORABLE') NULL,      -- proposition de l'agent (non décisive)
  ADD COLUMN avis_agent_motif VARCHAR(500) NULL,
  ADD COLUMN avis_agent_par_id BIGINT UNSIGNED NULL,
  ADD COLUMN date_avis_agent DATETIME NULL,
  ADD COLUMN decide_par_id BIGINT UNSIGNED NULL,                   -- chef qui a validé ou refusé
  ADD COLUMN date_decision DATETIME NULL,
  ADD KEY idx_recip_avis_par (avis_agent_par_id),
  ADD KEY idx_recip_decide_par (decide_par_id),
  ADD CONSTRAINT fk_recip_avis_par   FOREIGN KEY (avis_agent_par_id) REFERENCES compte_interne (id),
  ADD CONSTRAINT fk_recip_decide_par FOREIGN KEY (decide_par_id)     REFERENCES compte_interne (id),
  ADD CONSTRAINT ck_recip_avis CHECK (avis_agent IS NULL OR avis_agent_par_id IS NOT NULL),
  ADD CONSTRAINT ck_recip_decision CHECK (statut_validation = 'EN_ATTENTE' OR decide_par_id IS NOT NULL OR date_decision IS NULL);

ALTER TABLE demande_complement
  ADD COLUMN statut ENUM('BROUILLON','ENVOYEE','REPONDUE') NULL,   -- l'agent rédige (BROUILLON), le chef envoie
  ADD COLUMN redige_par_id BIGINT UNSIGNED NULL,
  ADD COLUMN envoye_par_id BIGINT UNSIGNED NULL,
  ADD COLUMN date_envoi DATETIME NULL,
  ADD KEY idx_dc_redige (redige_par_id),
  ADD KEY idx_dc_envoye (envoye_par_id),
  ADD CONSTRAINT fk_dc_redige  FOREIGN KEY (redige_par_id) REFERENCES compte_interne (id),
  ADD CONSTRAINT fk_dc_envoye  FOREIGN KEY (envoye_par_id) REFERENCES compte_interne (id);
UPDATE demande_complement SET statut = IF(date_reponse IS NULL, 'ENVOYEE', 'REPONDUE'), date_envoi = date_demande WHERE statut IS NULL;
ALTER TABLE demande_complement
  ADD CONSTRAINT ck_dc_statut CHECK (
    statut IS NOT NULL
    AND (statut = 'BROUILLON' OR (envoye_par_id IS NOT NULL OR date_envoi IS NOT NULL))
    AND (statut <> 'REPONDUE' OR date_reponse IS NOT NULL));

-- ---------------------------------------------------------------------
-- V5. Délégation rédigée par le DR seul
-- ---------------------------------------------------------------------
ALTER TABLE document_delegation
  ADD KEY idx_delegation_ceremonie (ceremonie_id),
  DROP INDEX uq_delegation_ceremonie,
  ADD COLUMN demandeur_id BIGINT UNSIGNED NULL AFTER ceremonie_id,
  ADD COLUMN version SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  ADD COLUMN est_active TINYINT(1) NOT NULL DEFAULT 1,
  ADD COLUMN redige_par_id BIGINT UNSIGNED NULL,                   -- compte DR
  ADD COLUMN date_redaction DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN numero_reference VARCHAR(60) NULL,                     -- n° sous « Direction de la Réglementation »
  ADD COLUMN libelle_entreprise VARCHAR(200) NULL,                  -- « de la SOBRAGA »
  ADD COLUMN date_fabrication DATE NULL,
  ADD COLUMN cle_active VARCHAR(40) GENERATED ALWAYS AS (IF(est_active = 1, CONCAT(ceremonie_id, '-', demandeur_id), NULL)) STORED,
  ADD KEY idx_delegation_demandeur (demandeur_id),
  ADD KEY idx_delegation_redige (redige_par_id),
  ADD UNIQUE KEY uq_delegation_version (ceremonie_id, demandeur_id, version),
  ADD UNIQUE KEY uq_delegation_active (cle_active),
  ADD CONSTRAINT fk_delegation_demandeur FOREIGN KEY (demandeur_id)  REFERENCES demandeur (id),
  ADD CONSTRAINT fk_delegation_redige    FOREIGN KEY (redige_par_id) REFERENCES compte_interne (id);
UPDATE document_delegation dd
   SET demandeur_id = (SELECT d.demandeur_id FROM participation p
                         JOIN recipiendaire r ON r.id = p.recipiendaire_id
                         JOIN dossier d ON d.id = r.dossier_id
                        WHERE p.ceremonie_id = dd.ceremonie_id LIMIT 1)
 WHERE demandeur_id IS NULL;
ALTER TABLE document_delegation
  ADD CONSTRAINT ck_delegation_demandeur CHECK (demandeur_id IS NOT NULL);

ALTER TABLE membre_delegation
  ADD COLUMN rang SMALLINT UNSIGNED NULL,                           -- 1 = autorité la plus élevée
  ADD COLUMN metal ENUM('OR','ARGENT','BRONZE') NULL,               -- ce que cette autorité décore
  ADD COLUMN est_autorite TINYINT(1) NOT NULL DEFAULT 0,            -- 1 = autorité qui décore ; 0 = membre de la délégation de l'entreprise
  ADD CONSTRAINT ck_membre_autorite CHECK (est_autorite = 0 OR (rang IS NOT NULL AND metal IS NOT NULL));

DELIMITER $$
CREATE TRIGGER trg_delegation_dr_seul BEFORE INSERT ON document_delegation
FOR EACH ROW BEGIN
  DECLARE v_role VARCHAR(30);
  SELECT role INTO v_role FROM compte_interne WHERE id = NEW.redige_par_id;
  IF NEW.redige_par_id IS NULL OR v_role IS NULL OR v_role <> 'DR' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la delegation est redigee par le DR seul';
  END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- V6. Ordre de recette émis par le CHEF seul, conforme à l'exemple confirmé
-- ---------------------------------------------------------------------
ALTER TABLE ordre_de_recette
  ADD COLUMN emis_par_id BIGINT UNSIGNED NULL,
  ADD KEY idx_ordre_emis_par (emis_par_id),
  ADD CONSTRAINT fk_ordre_emis_par FOREIGN KEY (emis_par_id) REFERENCES compte_interne (id);

DELIMITER $$
CREATE TRIGGER trg_ordre_chef_seul BEFORE INSERT ON ordre_de_recette
FOR EACH ROW BEGIN
  DECLARE v_poste VARCHAR(30);
  DECLARE v_apercu DECIMAL(14,2);
  SELECT poste_service INTO v_poste FROM compte_interne WHERE id = NEW.emis_par_id;
  IF NEW.emis_par_id IS NULL OR v_poste IS NULL OR v_poste <> 'CHEF_SERVICE' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'l ordre de recette est emis par le chef de service seul';
  END IF;
  SELECT apercu_ordre_montant INTO v_apercu FROM dossier WHERE id = NEW.dossier_id;
  IF v_apercu IS NULL OR v_apercu <> NEW.montant_total THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'le montant de l ordre doit etre celui de l exemple confirme par le demandeur';
  END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- V7. Quittance saisissable par le régisseur ; remise partielle ; stock saisissable
-- ---------------------------------------------------------------------
ALTER TABLE quittance
  ADD COLUMN mode_saisie ENUM('DEPOT_DEMANDEUR','SAISIE_REGISSEUR') NULL,
  ADD COLUMN saisi_par_id BIGINT UNSIGNED NULL,
  ADD KEY idx_quittance_saisi_par (saisi_par_id),
  ADD CONSTRAINT fk_quittance_saisi_par FOREIGN KEY (saisi_par_id) REFERENCES compte_interne (id);
UPDATE quittance SET mode_saisie = 'DEPOT_DEMANDEUR' WHERE mode_saisie IS NULL;
ALTER TABLE quittance
  ADD CONSTRAINT ck_quittance_mode CHECK (
    mode_saisie IS NOT NULL AND ((mode_saisie = 'SAISIE_REGISSEUR') = (saisi_par_id IS NOT NULL)));

ALTER TABLE remise_medailles
  ADD COLUMN saisi_par_id BIGINT UNSIGNED NULL,                    -- régisseur qui enregistre la remise
  ADD KEY idx_remise_saisi_par (saisi_par_id),
  ADD CONSTRAINT fk_remise_saisi_par FOREIGN KEY (saisi_par_id) REFERENCES compte_interne (id);

CREATE TABLE remise_ligne (                                         -- une ligne par métal et par remise : « combien payé, combien reçu »
  remise_id             BIGINT UNSIGNED NOT NULL,
  metal                 ENUM('OR','ARGENT','BRONZE') NOT NULL,
  quantite_payee        INT NOT NULL,                              -- médailles de ce métal payées (d'après l'ordre)
  quantite_deja_remise  INT NOT NULL,                              -- déjà remises par les remises précédentes
  quantite_recue        INT NOT NULL,                              -- reçues par le retirant lors de CETTE remise
  PRIMARY KEY (remise_id, metal),
  CONSTRAINT fk_remise_ligne_remise FOREIGN KEY (remise_id) REFERENCES remise_medailles (id),
  CONSTRAINT ck_remise_ligne CHECK (
    quantite_payee >= 0 AND quantite_deja_remise >= 0 AND quantite_recue >= 0
    AND quantite_deja_remise + quantite_recue <= quantite_payee)
) ENGINE=InnoDB COMMENT='Remise partielle : payées / déjà remises / reçues ; reste = payées - déjà remises - reçues';

ALTER TABLE mouvement_stock
  ADD COLUMN motif_type ENUM('LIVRAISON','REMISE','RETRAIT','CORRECTION','PERTE','AUTRE') NULL,
  ADD COLUMN remise_id  BIGINT UNSIGNED NULL,
  ADD COLUMN retrait_id BIGINT UNSIGNED NULL,
  ADD KEY idx_mvt_remise (remise_id),
  ADD KEY idx_mvt_retrait (retrait_id),
  ADD CONSTRAINT fk_mvt_remise  FOREIGN KEY (remise_id)  REFERENCES remise_medailles (id),
  ADD CONSTRAINT fk_mvt_retrait FOREIGN KEY (retrait_id) REFERENCES retrait_sans_ceremonie (id);
UPDATE mouvement_stock
   SET motif_type = IF(sens = 'ENTREE', IF(bon_livraison_id IS NOT NULL, 'LIVRAISON', 'CORRECTION'), 'REMISE')
 WHERE motif_type IS NULL;
ALTER TABLE mouvement_stock
  ADD CONSTRAINT ck_mvt_motif CHECK (
    motif_type IS NOT NULL
    AND (motif_type IN ('LIVRAISON','REMISE','RETRAIT') OR (motif IS NOT NULL AND compte_interne_id IS NOT NULL))
    AND (motif_type <> 'LIVRAISON' OR sens = 'ENTREE')
    AND (motif_type NOT IN ('REMISE','RETRAIT','PERTE') OR sens = 'SORTIE'));

CREATE OR REPLACE VIEW v_dossier_reste_a_remettre AS
SELECT doss.id AS dossier_id, m.metal AS metal,
       COUNT(*)                                  AS quantite_payee,
       SUM(m.remise_id IS NOT NULL)              AS quantite_remise,
       COUNT(*) - SUM(m.remise_id IS NOT NULL)   AS reste_a_remettre
  FROM medaille m
  JOIN recipiendaire r ON r.id = m.recipiendaire_id
  JOIN dossier doss    ON doss.id = r.dossier_id
 GROUP BY doss.id, m.metal;

-- ---------------------------------------------------------------------
-- V8. Bilan de cérémonie et « décoré »
-- ---------------------------------------------------------------------
ALTER TABLE participation
  ADD COLUMN decore TINYINT(1) NULL,                               -- NULL = bilan pas encore fait
  ADD COLUMN motif_non_decore VARCHAR(255) NULL,
  ADD COLUMN bilan_saisi_par_id BIGINT UNSIGNED NULL,
  ADD COLUMN date_bilan DATETIME NULL,
  ADD KEY idx_part_bilan_par (bilan_saisi_par_id),
  ADD CONSTRAINT fk_part_bilan_par FOREIGN KEY (bilan_saisi_par_id) REFERENCES compte_interne (id),
  ADD CONSTRAINT ck_part_bilan CHECK (
    decore IS NULL OR (bilan_saisi_par_id IS NOT NULL AND (decore = 1 OR motif_non_decore IS NOT NULL)));

CREATE TABLE bilan_ceremonie (                                      -- le bilan d'un dossier pour une cérémonie
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id       BIGINT UNSIGNED NOT NULL,
  ceremonie_id     BIGINT UNSIGNED NOT NULL,
  tous_decores     TINYINT(1) NOT NULL,                            -- 1 = case « tous les récipiendaires ont été décorés » cochée
  saisi_par_id     BIGINT UNSIGNED NOT NULL,                       -- AGENT ou CHEF_SERVICE
  date_bilan       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  commentaire      VARCHAR(500) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_bilan (dossier_id, ceremonie_id),
  KEY idx_bilan_ceremonie (ceremonie_id),
  KEY idx_bilan_par (saisi_par_id),
  CONSTRAINT fk_bilan_dossier   FOREIGN KEY (dossier_id)   REFERENCES dossier (id),
  CONSTRAINT fk_bilan_ceremonie FOREIGN KEY (ceremonie_id) REFERENCES ceremonie (id),
  CONSTRAINT fk_bilan_par       FOREIGN KEY (saisi_par_id) REFERENCES compte_interne (id)
) ENGINE=InnoDB COMMENT='Bilan post-cérémonie : tous décorés, ou liste des non décorés (participation.decore)';

CREATE OR REPLACE VIEW v_dossier_bilan AS
SELECT doss.id AS dossier_id,
       SUM(r.statut_validation = 'VALIDE') AS nb_valides,
       SUM(r.statut_validation = 'VALIDE' AND (
             EXISTS (SELECT 1 FROM participation p WHERE p.recipiendaire_id = r.id AND p.decore = 1)
          OR EXISTS (SELECT 1 FROM retrait_sans_ceremonie rs WHERE rs.recipiendaire_id = r.id AND rs.date_retrait IS NOT NULL)
       )) AS nb_decores
  FROM dossier doss
  JOIN recipiendaire r ON r.dossier_id = doss.id
 GROUP BY doss.id;

-- ---------------------------------------------------------------------
-- V9. Propositions de cérémonie par le demandeur ; le Service confirme ou refuse
-- ---------------------------------------------------------------------
CREATE TABLE ceremonie_proposition (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dossier_id         BIGINT UNSIGNED NOT NULL,
  demandeur_id       BIGINT UNSIGNED NOT NULL,
  ceremonie_id       BIGINT UNSIGNED NULL,                         -- renseigné quand le Service confirme
  date_souhaitee     DATE NOT NULL,
  lieu_souhaite      VARCHAR(200) NOT NULL,
  message            VARCHAR(1000) NULL,
  statut             ENUM('EN_ATTENTE','CONFIRMEE','REFUSEE','ANNULEE') NULL,
  motif_refus        VARCHAR(500) NULL,
  propose_par_id     BIGINT UNSIGNED NULL,                         -- utilisateur (demandeur) ; NULL si saisie par un agent
  saisi_par_id       BIGINT UNSIGNED NULL,                         -- agent qui a saisi pour un demandeur sans compte
  decide_par_id      BIGINT UNSIGNED NULL,                         -- CHEF_SERVICE
  date_proposition   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_decision      DATETIME NULL,
  ouverte_pour_dossier_id BIGINT UNSIGNED GENERATED ALWAYS AS (IF(statut = 'EN_ATTENTE', dossier_id, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_prop_ouverte (ouverte_pour_dossier_id),            -- une seule proposition ouverte par dossier
  KEY idx_prop_dossier (dossier_id),
  KEY idx_prop_demandeur (demandeur_id),
  KEY idx_prop_ceremonie (ceremonie_id),
  CONSTRAINT fk_prop_dossier   FOREIGN KEY (dossier_id)     REFERENCES dossier (id),
  CONSTRAINT fk_prop_demandeur FOREIGN KEY (demandeur_id)   REFERENCES demandeur (id),
  CONSTRAINT fk_prop_ceremonie FOREIGN KEY (ceremonie_id)   REFERENCES ceremonie (id),
  CONSTRAINT fk_prop_propose   FOREIGN KEY (propose_par_id) REFERENCES utilisateur (id),
  CONSTRAINT fk_prop_saisi     FOREIGN KEY (saisi_par_id)   REFERENCES compte_interne (id),
  CONSTRAINT fk_prop_decide    FOREIGN KEY (decide_par_id)  REFERENCES compte_interne (id),
  CONSTRAINT ck_prop_statut CHECK (
    statut IS NOT NULL
    AND (statut <> 'REFUSEE'   OR motif_refus IS NOT NULL)
    AND (statut <> 'CONFIRMEE' OR (ceremonie_id IS NOT NULL AND decide_par_id IS NOT NULL))
    AND (propose_par_id IS NOT NULL OR saisi_par_id IS NOT NULL))
) ENGINE=InnoDB COMMENT='Le demandeur propose, le Service confirme ou refuse (pas de contre-proposition)';

CREATE TABLE ceremonie_proposition_recipiendaire (
  proposition_id    BIGINT UNSIGNED NOT NULL,
  recipiendaire_id  BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (proposition_id, recipiendaire_id),
  CONSTRAINT fk_cpr_prop  FOREIGN KEY (proposition_id)   REFERENCES ceremonie_proposition (id),
  CONSTRAINT fk_cpr_recip FOREIGN KEY (recipiendaire_id) REFERENCES recipiendaire (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- V10. Brouillon de dossier côté serveur
-- ---------------------------------------------------------------------
CREATE TABLE brouillon_dossier (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  demandeur_id   BIGINT UNSIGNED NOT NULL,
  campagne_id    BIGINT UNSIGNED NOT NULL,
  donnees        JSON NOT NULL,                                    -- contenu de l'assistant (jamais de CNI en clair dans les journaux)
  date_creation  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_maj       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  statut         ENUM('ACTIF','CONVERTI') NULL,
  dossier_id     BIGINT UNSIGNED NULL,                             -- dossier créé à partir du brouillon
  ouvert_pour_cle VARCHAR(40) GENERATED ALWAYS AS (IF(statut = 'ACTIF', CONCAT(demandeur_id, '-', campagne_id), NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_brouillon_actif (ouvert_pour_cle),                 -- un brouillon actif par demandeur et par campagne
  KEY idx_brouillon_demandeur (demandeur_id),
  CONSTRAINT fk_brouillon_demandeur FOREIGN KEY (demandeur_id) REFERENCES demandeur (id),
  CONSTRAINT fk_brouillon_campagne  FOREIGN KEY (campagne_id)  REFERENCES campagne (id),
  CONSTRAINT fk_brouillon_dossier   FOREIGN KEY (dossier_id)   REFERENCES dossier (id),
  CONSTRAINT ck_brouillon_statut CHECK (statut IS NOT NULL AND (statut <> 'CONVERTI' OR dossier_id IS NOT NULL))
) ENGINE=InnoDB COMMENT='Brouillon du nouveau dossier ; sans effet sur dossier tant qu''il n''est pas déposé';
