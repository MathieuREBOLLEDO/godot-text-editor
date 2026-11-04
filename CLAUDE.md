# Text Editor (addon Godot)

Addon Godot 4.x : onglet « Texts » de l'éditeur, tous les textes du jeu
(clés, traductions, dialogues en graphe, CSV des traducteurs, validation,
fichiers pour le jeu). GDScript typé uniquement. Mode d'emploi : README.md ;
format des fichiers : FORMAT.md.

## Règles de travail
- Ne pas ajouter de systèmes ou de fonctionnalités non demandés.
- Privilégier le code simple et lisible plutôt qu'une architecture générique.
- Expliquer les choix importants et signaler les compromis.
- Tester ce qui peut l'être et annoncer clairement ce qui n'a pas été vérifié.
- Ne pas modifier l'architecture sans proposer un plan avant et attendre
  validation.
- Ne pas commiter sans qu'on le demande.

## Contraintes de l'addon
- Aucune dépendance : ni autre addon, ni fichier du projet qui l'utilise.
- Tous les chemins en res://addons/text_editor/...
- Comme les autres addons : get_editor_interface() plutôt que le singleton
  EditorInterface, pas de dictionnaires typés.
- Seule classe globale : DialogueRunner (runtime/, utilisable en jeu).
- core/ et runtime/ ne dépendent pas de l'interface ; runtime/ ne dépend pas
  de core/ (il part avec le jeu exporté).
- Format des fichiers : un changement monte Migrations.SCHEMA et ajoute une
  étape dans core/migrations.gd, puis met à jour FORMAT.md et les références
  de tests/expected/.
- Dépôt Git à part (github.com/MathieuREBOLLEDO/godot-text-editor, branche
  main ; clone local G:\Projects\Godot_Addons\godot-text-editor), sous-module
  addons/text_editor des jeux : un commit ici part dans ce dépôt.

## Fichiers
- plugin.gd : EditorPlugin, onglet « Texts », réglage text_editor/data_dir.
- core/text_db.gd : la base (projet, entrées, statuts, historique,
  dialogues), lecture et écriture des JSON.
- core/migrations.gd : version du format.
- core/csv_io.gd : CSV des traducteurs (format, export, import en deux temps).
- core/dialogue_data.gd : nœuds, liens, déroulé narratif, copie pour le jeu.
- core/validator.gd : contrôles (entrées, tokens, longueurs, dialogues).
- core/exporter.gd : fichiers du jeu, déclaration des traductions.
- core/text_diff.gd : comparaison mot à mot.
- runtime/dialogue_runner.gd (DialogueRunner), runtime/text_tokens.gd.
- editor/main_view.gd : l'onglet (en-tête, rail, pied, sauvegarde auto,
  annulation) ; une vue par espace (dashboard_view, database_view,
  dialogue_view + dialogue_narrative + dialogue_preview, localization_view,
  import_export_view, qa_view, settings_view).
- editor/text_theme.gd : jetons de design et thème (copie des défauts communs
  aux addons, voir DESIGN.md de game_feel) ; editor/widgets.gd : briques.
- editor/texts.gd : textes (anglais de référence, français).

## Règles d'interface
- Textes en anglais, via texts.gd ; commentaires en français. La racine
  coupe la traduction automatique de l'éditeur (auto_translate_mode).
- Pas de couleur en dur dans les écrans : text_theme.gd (sauf les couleurs
  propres au jeu : personnages, boîte de l'aperçu).

## Test
- Chargement sans erreur, dans un jeu qui utilise l'addon (RoguePinball) :
  `"G:\GameEngine\Godot 4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "G:\Projects\Godot\RoguePinball" --quit`
- Tests automatiques : `.\tests\run_tests.ps1 -Dir res://addons/text_editor`
  dans un jeu qui a l'addon et le test runner. Quel test pour quel système :
  tests/impact.md ; une nouvelle fonction arrive avec ses tests et sa ligne.
- Capture de l'onglet : un script (hors projet, load() d'un chemin absolu)
  appelé depuis plugin._enter_tree sous une variable d'environnement, qui
  prépare des données dans user://, choisit l'onglet
  (EditorInterface.set_main_screen_editor("Texts")), enregistre le viewport
  de chaque espace en PNG et quitte ; éditeur lancé avec `--editor
  --resolution 1600x900 --quit-after 30000`. Retirer l'appel ensuite et
  vérifier avec git status que project.godot n'a pas gardé le dossier de
  test.
