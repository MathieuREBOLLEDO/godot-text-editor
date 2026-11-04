# Text Editor (addon Godot 4)

Onglet **Texts** de l'éditeur : la source unique de tous les textes du jeu.
Chaque texte a une clé stable (`MENU_PLAY`), une catégorie, un contexte, une
description pour les traducteurs, des tags, une limite de longueur, un texte
par langue et un statut par langue. Les dialogues se construisent en graphe
et référencent ces clés.

Interface en anglais par défaut ; langue dans *Paramètres de l'éditeur >
text_editor/language*. Thème : jetons communs aux addons, remplaçables par
`res://design_tokens.cfg`.

## Espaces (Alt+1…7)

| Espace | Rôle |
|---|---|
| Dashboard | Nombre de textes, dialogues, langues ; avancement par langue ; ce qui demande de l'attention (accès direct). |
| Database | Tableau paginé, recherche, filtres (catégorie, statut, langue, tag), tri par colonne, cellules modifiables, sélection multiple et modifications en lot, inspecteur de l'entrée. Ctrl+Z annule. |
| Dialogues | Graphe (Start, Line, Choice, Branch, Condition, Variable check, Event, Jump, End), vue narrative modifiable, aperçu jouable (langue, plateforme, conditions, variables). |
| Localization | Source à gauche, traduction à droite, contexte, longueur et tokens vérifiés à la frappe, statut, historique et comparaison mot à mot. Ctrl+Entrée : enregistrer et suivant. |
| Import / Export | CSV pour traducteurs (filtres), import avec aperçu et conflits, fichiers du jeu. |
| Validation & QA | Validation globale, explication de chaque problème, double-clic pour y aller. |
| Settings | Langues, catégories, plateformes, tokens, limites, personnages, dossiers, police vérifiée. |

## Données

Dossier `res://game/ui/texts` par défaut (réglage du projet
`text_editor/data_dir`). JSON triés et stables, faits pour Git ; format
détaillé dans [FORMAT.md](FORMAT.md).

- Enregistrement automatique peu après chaque changement.
- Le texte source change : ses traductions passent *Needs review*, jamais
  effacées (aussi après une modification hors de l'outil, ex. fusion Git).
- Une clé présente dans deux fichiers est gardée deux fois (la seconde
  renommée `_DUPLICATE`) et signalée.
- Un fichier illisible ou d'une version plus récente bloque l'écriture : rien
  ne se perd.

## CSV des traducteurs

Colonnes `Key, Category, Context, Description, Tags, Max Length`, une par
langue (`French [fr]`), `Revision`. UTF-8 avec BOM, CRLF, séparateur `,` ou
`;` (Excel FR), guillemets et retours à la ligne gérés. À l'import : aperçu
de chaque changement, rien n'est écrit avant « Apply » ; une cellule vide
n'efface jamais ; une ligne modifiée dans l'outil depuis l'export donne des
*conflits*, décochés par défaut ; nouvelles clés ajoutées, colonnes
inconnues signalées.

## Dans le jeu

- Textes simples : *Import / Export > Export game files* écrit
  `export/texts.csv` (format de traduction de Godot), *Register in Godot*
  déclare les `.translation` (modifie project.godot), puis `tr("MENU_PLAY")`.
- Tokens : `{INTERACT_BUTTON}` reste dans chaque traduction ; valeur par
  plateforme dans Settings, `export/tokens.json`.
- Dialogues : `DialogueRunner` (seule classe globale de l'addon) lit
  `export/dialogues/<id>.json` :

```gdscript
const TextTokens = preload("res://addons/text_editor/runtime/text_tokens.gd")

var runner := DialogueRunner.load_file("res://game/ui/texts/export/dialogues/village.json")
runner.variables = {"gold": 10}
var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/ui/texts/export/tokens.json"))
runner.tokens = TextTokens.for_platform(table, "xbox")
runner.event_handler = func(name: String, args: String) -> void: print(name, args)
var step := runner.start()
# step.type == "line"   : step.speaker_name, step.text, step.color, step.portrait → runner.next()
# step.type == "choice" : step.options[i].text → runner.choose(step.options[i].index)
# step.type == "end"
```

Conditions : `condition_handler` (func(expression) -> bool) ou, sans lui,
`variables` (« met » vrai si la variable l'est, « !met » l'inverse).

## Tests

Dans un jeu qui a l'addon et le test runner :
`.\tests\run_tests.ps1 -Dir res://addons/text_editor`. Carte : tests/impact.md.
