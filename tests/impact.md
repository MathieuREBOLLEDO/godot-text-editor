# Carte d'impact des tests

Quand un système change : lancer ses tests pendant le travail, puis tous
les tests de l'addon (environ 2 s) avant d'annoncer la tâche finie.

Les tests tournent dans un jeu qui a l'addon et le test runner (RoguePinball,
ProjetGringo…) : `.\tests\run_tests.ps1 -Dir res://addons/text_editor`, ou
un seul avec `-Filter <texte>`. Les fichiers lus et écrits sont dans
user://test_runner/text_editor/ : aucun fichier du jeu n'est touché.

| Système (fichiers) | Ses tests | Touche aussi |
|---|---|---|
| Tout fichier de l'addon (chargement) | `-Filter addon_files_load` | — |
| Textes de l'onglet (editor/texts.gd) | `-Filter translated`, `-Filter text_keys_in_code`, `-Filter raw_keys` | — |
| Base (core/text_db.gd), migrations | `-Filter test_text_db` | CSV, export, validation |
| Statuts, Needs review, historique | `-Filter review`, `-Filter history`, `-Filter statuses` | Localization |
| CSV (core/csv_io.gd) | `-Filter csv` | Import / Export |
| Dialogues (core/dialogue_data.gd), DialogueRunner | `-Filter test_dialogues` | graphe, narratif, aperçu |
| Validation (core/validator.gd) | `-Filter test_validator` | QA, Dashboard |
| Export (core/exporter.gd), comparaison (text_diff.gd) | `-Filter test_export` | fichiers du jeu |
| Format des fichiers (non-régression) | `-Filter expected` | tout : relire le diff de tests/expected/ |
| Onglet (editor/*.gd) | `-Filter test_editor_ui` | — |

Non-régression : `test_export_matches_expected_files` compare octet pour
octet l'export, le CSV et les fichiers de données de la base d'exemple à
tests/expected/ (en .txt). Un changement voulu du format : relancer avec
`$env:TEXT_EDITOR_UPDATE_EXPECTED="1"`, relire le diff, commiter.

## Pas couvert (à vérifier à la main)

Le rendu (captures, voir CLAUDE.md), le glisser-déposer dans le graphe
(liens tirés à la souris, déplacement des nœuds), les fenêtres de fichier
de l'éditeur (EditorFileDialog), Ctrl+Z dans l'éditeur (EditorUndoRedoManager
absent hors éditeur), l'ouverture du CSV dans Excel / Google Sheets /
LibreOffice, la déclaration des traductions dans project.godot et tr() en
jeu après import par Godot.
