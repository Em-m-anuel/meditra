# Prototypes frontend MÉDITRA

Pages HTML autonomes, sans backend, framework, compilation, fichier CSS ou fichier JavaScript partagé. Les styles et scripts sont intégrés à chaque fichier. Toutes les données sont fictives.

## Direction visuelle

Toutes les pages suivent la charte de `profil-test.html` : menu latéral vert avec liseré or, barre du haut claire avec fil d'Ariane, cartes blanches aux bordures fines, chiffres en DM Serif Display, interface en Manrope, pastilles de statut douces et bandeaux verts décorés d'une médaille. Sur tablette et mobile, le menu latéral devient un panneau coulissant.

Animations : apparition progressive des blocs, comptage des indicateurs, croissance des graphiques, effet d'onde sur les boutons, ouverture animée des fenêtres et notifications avec barre de temps.

Les polices sont chargées depuis Google Fonts ; sans connexion, les pages basculent sur des polices système. La déconnexion mène à `meditra-connexion.html`, inclus dans ce dossier avec `chargement.html`.

## Pages créées

### Demandeur

- `demandeur-dashboard.html`
- `demandeur-dossiers.html`
- `demandeur-nouveau-dossier.html`
- `demandeur-detail-dossier.html`
- `demandeur-ceremonies.html`
- `demandeur-notifications.html`
- `demandeur-profil.html`

### Secrétariat

- `secretaire-dashboard.html`
- `secretaire-dossiers.html`
- `secretaire-notifications.html`
- `secretaire-registre.html`
- `secretaire-profil.html`

### DGT

- `dgt-dashboard.html`
- `dgt-notifications.html`
- `dgt-profil.html`

### Ministre

- `ministre-dashboard.html`
- `ministre-notifications.html`
- `ministre-profil.html`

### Directeur régional

- `dr-dashboard.html`
- `dr-dossiers.html`
- `dr-notifications.html`
- `dr-registre.html`
- `dr-profil.html`

### Chef de service

- `chef-service-dashboard.html`
- `chef-service-dossiers.html`
- `chef-service-ordre-recette.html (complément dédié demandé)`
- `chef-service-archivage.html`
- `chef-service-notifications.html`
- `chef-service-registre.html`
- `chef-service-profil.html`

### Agent

- `agent-dashboard.html`
- `agent-dossiers.html`
- `agent-archivage.html`
- `agent-notifications.html`
- `agent-registre.html`
- `agent-profil.html`

### Régisseur

- `regisseur-dashboard.html`
- `regisseur-dossiers.html`
- `regisseur-stock.html`
- `regisseur-registre-stock.html`
- `regisseur-notifications.html`
- `regisseur-profil.html`

## Mode d’emploi

Ouvrir `index.html` pour le catalogue, ou ouvrir directement n’importe quel fichier HTML. Garder les fichiers dans le même dossier pour que les liens relatifs entre pages fonctionnent. Les interactions modifient uniquement des données fictives en mémoire ou dans `localStorage` du navigateur.

## Vérifications automatisées

La génération et les vérifications statiques du HTML et des scripts intégrés sont effectuées dans l’environnement de travail. Aucun backend, appel API, framework, ressource CDN ou bundler n’est requis. La vérification manuelle dans un navigateur réel n’est pas disponible dans cet environnement ; voir l’état des tests dans la réponse de livraison.
