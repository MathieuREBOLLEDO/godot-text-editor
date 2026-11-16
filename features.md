# Features

Registre des fonctionnalités de l'addon : une fiche par fonction, avec son
but, ses interactions et les documents qui la décrivent. Lu par Project Hub
(onglet Features), au même format que le mecaniques.md d'un jeu. Tenu à
jour par Claude quand il crée, change ou coupe une fonction.

Format d'une fiche (garder les noms de champs, une ligne chacun) :
- `type` : famille de la fonction (espace, données, jeu, propre au jeu).
- `parent` : titre de la fiche qui la regroupe (facultatif).
- `statut` : à définir, à faire, en cours, à retravailler, fait ou coupé.
- `but` : à quoi elle sert, en une phrase.
- `commandes` : gestes ou raccourcis, « ; » entre deux.
- `relations` : une sous-ligne par interaction, « ce qu'on touche → effet ».
- `liens` : autres fiches liées, par leur titre.
- `docs` : fichier.md › section ; « ; » entre deux.
- `tests` : noms des fichiers de test, « ; » entre deux (facultatif).
- `projets` : projets pour lesquels la fonction est propre, « ; » entre
  deux. Sans ce champ, la fonction est commune à tous les jeux.

## Onglet Texts
- type : espace
- statut : fait
- but : la source unique de tous les textes du jeu, une clé stable par texte.
- commandes : Alt+1 à Alt+7 : changer d'espace
- relations :
  - Texte → catégorie, contexte, description, tags, limite de longueur, un texte et un statut par langue
- docs : README.md › Espaces (Alt+1…7)
- tests : test_editor_ui

## Dashboard
- type : espace
- parent : Onglet Texts
- statut : fait
- but : avancement par langue et ce qui demande de l'attention, avec accès direct.
- docs : README.md › Espaces (Alt+1…7)

## Database
- type : espace
- parent : Onglet Texts
- statut : fait
- but : tous les textes en tableau, recherche, filtres, tri et modifications en lot.
- commandes : Ctrl+Z : annuler
- docs : README.md › Espaces (Alt+1…7)
- tests : test_text_db

## Dialogues
- type : espace
- parent : Onglet Texts
- statut : fait
- but : construire les dialogues en graphe et les jouer dans un aperçu.
- relations :
  - Nœuds → Start, Line, Choice, Branch, Condition, Variable check, Event, Jump, End
  - Vue narrative → le dialogue en texte, modifiable
  - Aperçu → langue, plateforme, conditions, variables
- docs : README.md › Espaces (Alt+1…7)
- tests : test_dialogues

## Localization
- type : espace
- parent : Onglet Texts
- statut : fait
- but : traduire avec la source à côté, longueur et tokens vérifiés à la frappe.
- commandes : Ctrl+Entrée : enregistrer et passer au suivant
- relations :
  - Historique → comparaison mot à mot des versions
- docs : README.md › Espaces (Alt+1…7)

## Import et export CSV
- type : données
- statut : fait
- but : envoyer les textes aux traducteurs en CSV et reprendre leur travail sans rien perdre.
- relations :
  - Import → aperçu de chaque changement avant Apply, une cellule vide n'efface jamais
  - Ligne modifiée dans l'outil depuis l'export → conflit, décoché par défaut
- docs : README.md › CSV des traducteurs
- tests : test_csv

## Validation et QA
- type : espace
- parent : Onglet Texts
- statut : fait
- but : liste des problèmes de tous les textes, chacun expliqué, double-clic pour y aller.
- docs : README.md › Espaces (Alt+1…7)
- tests : test_validator

## Données suivies par Git
- type : données
- statut : fait
- but : des JSON triés et stables, enregistrés tout seuls, qui ne perdent rien.
- relations :
  - Texte source changé → ses traductions passent Needs review
  - Clé en double → gardée deux fois et signalée
  - Fichier illisible ou plus récent → écriture bloquée
- docs : README.md › Données ; FORMAT.md
- tests : test_text_db

## Textes dans le jeu
- type : jeu
- statut : fait
- but : utiliser les textes avec tr() et jouer les dialogues avec DialogueRunner.
- relations :
  - Export game files → export/texts.csv et .translation déclarés dans Godot
  - Tokens ({INTERACT_BUTTON}) → valeur par plateforme
  - DialogueRunner → lignes, choix, conditions, événements
- docs : README.md › Dans le jeu
- tests : test_export

## Textes de RoguePinball
- type : propre au jeu
- statut : fait
- but : les textes des menus de RoguePinball, en anglais et en français.
- projets : RoguePinball
