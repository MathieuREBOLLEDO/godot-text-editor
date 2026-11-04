# Format des données (schema 1)

Tous les fichiers sont du JSON UTF-8, clés triées, indentation par
tabulations, une ligne vide finale. Mêmes données = mêmes octets : les diffs
Git ne montrent que ce qui a changé. Chaque fichier porte `"schema"` ; un
fichier sans schema est en version 1, un fichier plus récent que l'addon
n'est jamais réécrit (core/migrations.gd).

## Dossier des données (`text_editor/data_dir`, défaut res://game/ui/texts)

### project.json

```json
{
	"categories": ["ui", "menu", "dialogue", "..."],
	"characters": {"merchant": {"color": "#e0a040", "name_key": "CHAR_MERCHANT", "portrait": "res://..."}},
	"export_dir": "export",
	"font": "",
	"languages": ["en", "fr", "de"],
	"limits": {"ui": 24, "ui@switch": 18},
	"platforms": ["pc", "playstation", "xbox", "switch", "steam_deck"],
	"preview": {"box_width": 640, "font_size": 18, "box_color": "#11151b", "text_color": "#f2f2f2"},
	"schema": 1,
	"source_language": "en",
	"tokens": {"INTERACT_BUTTON": {"default": "E", "playstation": "Cross", "xbox": "A"}}
}
```

Limites : `categorie` pour toutes les plateformes, `categorie@plateforme`
pour une seule ; `max_length` d'une entrée passe avant.

### strings/<categorie>.json

```json
{
	"category": "ui",
	"entries": {
		"MENU_PLAY": {
			"category": "ui", "context": "Main Menu", "description": "", "max_length": 0,
			"modified": "2026-11-04T10:00:00", "tags": ["main_menu"],
			"texts": {
				"en": {"history": [], "modified": "", "text": "Play"},
				"fr": {"history": [{"date": "...", "text": "Lancer"}], "modified": "...",
					"source_hash": "de3c731be5", "status": "translated", "text": "Jouer"}
			}
		}
	},
	"schema": 1
}
```

- Clé : `^[A-Z][A-Z0-9_]*$`, unique dans tout le projet.
- Statuts : `missing`, `to_translate`, `translated`, `needs_review`,
  `approved`. Une langue sans texte est `missing` (ou `to_translate` si on l'a
  marquée ainsi).
- `source_hash` : empreinte du texte source au moment de la traduction ; s'il
  ne correspond plus, la traduction passe `needs_review` au chargement.
- `history` : les 10 dernières versions, la plus récente d'abord.

### dialogues/<id>.json

```json
{
	"links": [["n1", 0, "n2"], ["n2", 0, "n3"]],
	"next_id": 4,
	"nodes": {
		"n1": {"position": [0, 0], "type": "start"},
		"n2": {"position": [300, 0], "speaker": "merchant", "text_key": "DLG_HELLO", "type": "line"},
		"n3": {"options": [{"condition": "", "text_key": "DLG_ASK"}], "position": [600, 0], "type": "choice"}
	},
	"schema": 1
}
```

Lien : `[nœud de départ, numéro de sortie, nœud d'arrivée]`, une sortie mène
à un seul nœud. Ids stables (`n<next_id>`, jamais réutilisés).

| type | champs | sorties |
|---|---|---|
| start | — | 1 |
| line | speaker, text_key | 1 |
| choice | options: [{text_key, condition}] | 1 par option |
| branch | conditions: [expression] | 1 par condition + sinon |
| condition | expression | 2 (vrai, faux) |
| variable_check | variable, operator (== != < <= > >=), value | 2 (vrai, faux) |
| event | name, args | 1 |
| jump | target (id d'un nœud) | 0 |
| end | — | 0 |

## Export pour le jeu (`<data_dir>/export/`)

| Fichier | Contenu |
|---|---|
| texts.csv | `keys,en,fr,…` : CSV de traduction de Godot (importé en texts.<langue>.translation). |
| json/<langue>.json | `{ "CLE": "texte" }`, traductions manquantes remplacées par la source (option). |
| dialogues/<id>.json | Le dialogue sans positions, avec `characters` (ceux qu'il utilise). |
| tokens.json | La table des tokens par plateforme. |
| manifest.json | schema, source_language, languages, dialogues, entries, platforms. |

Unity / Unreal / autre : lire `json/<langue>.json` pour les textes et
`dialogues/*.json` en suivant `links` depuis le nœud `start` (comme
runtime/dialogue_runner.gd).

## CSV des traducteurs

`Key, Category, Context, Description, Tags, Max Length, <Langue> [code]…,
Revision`. Revision = empreinte de la ligne à l'export (changements faits
dans l'outil depuis → conflits à l'import).
