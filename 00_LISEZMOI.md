# MÉDITRA — Dossier à donner à l'agent de développement (v6)

Donnez **tout ce dossier** au nouvel agent, puis envoyez-lui comme premier message le contenu de `01_prompt_agent_meditra_v6.md`.

| Fichier | Contenu |
|---|---|
| `01_prompt_agent_meditra_v6.md` | Le prompt : méthode de travail, stack, base de données, conversion du front en Blade, ordre des étapes, tests, rapport final. |
| `02_regles_back_v2.0.md` | Toutes les règles métier (v1.0 + décisions v5), la matrice des permissions, la machine à états T1–T13, les codes d'erreur, les extensions de schéma autorisées et les questions encore ouvertes avec leur valeur par défaut. |
| `03_sql/distinctions_nationales_v4.sql` | Schéma de départ. |
| `03_sql/migration_v5_depuis_v4.sql` | Migration v4 → v5, à appliquer après la v4. |
| `03_sql/seed_pays_complet_v4.sql` | **À ajouter par vous** : la liste complète des pays et nationalités. |
| `04_front/` | 42 pages des 8 profils dans la charte du profil test, la page de connexion, l'écran de chargement, `profil-test.html` (référence de la charte) et `index.html` (catalogue de démonstration, non livré dans l'application). |

## Décisions de cadrage (26 octobre 2026)

- Nouveau projet Laravel vierge (pas de reprise de l'ancien dépôt).
- L'agent exécute lui-même migrations et tests, en une seule passe, et ne rend qu'un rapport final.
- L'agent crée les écrans manquants (administrateur, dépôt physique, délégation du DR, cérémonies et bilan…) dans la charte.
- Un seul profil Secrétariat ; aucun choix de destinataire : dossiers, recours et relances passent tous par le DR.
- L'agent peut modifier le front quand il ne correspond pas aux données du back, sans toucher à la charte (prompt, section 6.3).

## À relire avant de lancer l'agent

Les 12 questions ouvertes de la **section 26 des règles**. L'agent appliquera les valeurs par défaut indiquées si vous ne les changez pas. Les plus importantes : Q2 (dossiers visibles par le régisseur) et Q7 (versions de la quittance, seule modification d'une clé existante).
