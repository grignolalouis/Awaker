<p align="center">
  <img src="Assets/banner.png" alt="Awaker" width="800">
</p>

Awaker garde ton Mac éveillé, **même capot fermé**, et te montre où en sont tes agents Claude Code.
Tu lances une tâche, tu fermes le capot, le travail continue.

## Ce que ça fait

- **Sessions capot fermé** : un bouton pour garder le Mac éveillé, pour une durée ou sans limite.
- **Mode auto** : le Mac reste éveillé tant qu'un agent travaille, et reprend sa veille normale 3 minutes après.
- **Suivi des agents** : qui travaille, qui t'attend, qui a terminé, avec ta dernière demande, sa réponse, le temps et le coût.
- **Notifications** : quand un agent termine ou a besoin de toi, et un récapitulatif à ton retour devant le Mac.
- **Protections** : arrêt automatique si la batterie est faible, si le chargeur est débranché ou si le Mac surchauffe.
- **Barre des menus** : tout est accessible sans ouvrir la fenêtre.

## Installer

Il faut un Mac Apple Silicon sous macOS 26.

1. Télécharge `Awaker.dmg` depuis la [dernière version](https://github.com/grignolalouis/Awaker/releases/latest).
2. Glisse Awaker dans Applications et ouvre-le.
3. macOS bloque le premier lancement, car l'app n'est pas signée par un compte développeur Apple. Va dans
   Réglages Système > Confidentialité et sécurité, puis clique sur « Ouvrir quand même ». C'est à faire une seule fois.
4. Dans Awaker, clique sur « Installer l'autorisation… » et tape ton mot de passe administrateur.

Ensuite Awaker se met à jour tout seul, depuis Réglages > Mises à jour.

## Comment ça marche

Fermer le capot force la mise en veille, et seule la commande système `pmset disablesleep` l'empêche.
Elle demande les droits administrateur : Awaker installe donc une règle limitée à cette seule commande, et rien d'autre.
Quitter Awaker rend toujours au Mac sa veille normale.

Le suivi des agents lit, en lecture seule, les fichiers que Claude Code tient dans `~/.claude`. Rien ne quitte ton Mac.

Capot fermé, le Mac ne dort plus : ne le range pas dans un sac pendant une session, il chauffe.

## Développer

Les Command Line Tools suffisent, pas besoin d'Xcode.

```sh
Scripts/build.sh --install    # construit et installe dans /Applications
Scripts/test.sh               # lance les tests
Scripts/make-dmg.sh           # construit build/Awaker.dmg
```

Pour publier une version, change le numéro dans `VERSION` et pousse sur `main` : la CI teste, construit le DMG et publie
la release. Les apps installées la détectent dans la journée.

## Crédits

L'illustration de fond est utilisée avec l'accord de son auteur. Awaker n'est pas affilié à Anthropic.
