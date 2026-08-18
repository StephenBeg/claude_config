---
name: sonarqube
description: Use when analyzing SonarQube issues, code quality, coverage, or security vulnerabilities for a project
---

# SonarQube Skill

## MCP Server

Transport : stdio via Docker (`mcp/sonarqube`).
Config dans `~/.claude.json` sous `mcpServers.sonarqube`.

**Variables à configurer** (remplacer les placeholders) :
- `SONARQUBE_TOKEN` — token personnel SonarQube (Profil → Security → Generate Token)
- `SONARQUBE_URL` — URL du serveur Malt (demander l'URL exacte à l'équipe ou chercher dans les secrets CI GitLab)

## Comportement attendu

Les outils MCP SonarQube exposent :
- Recherche de projets (`search_projects`)
- Issues par sévérité/type (`get_issues`)
- Métriques de couverture (`get_measures`)
- Hotspots de sécurité (`get_hotspots`)
- Qualité gate (`get_quality_gate`)

## Workflow type — analyser un module

1. Identifier le `projectKey` du module (format dans `sonar-project.properties` ou CI)
2. Récupérer les issues actives : sévérité BLOCKER/CRITICAL en priorité
3. Croiser avec la couverture de test pour identifier les lacunes
4. Recommander corrections par ordre de criticité

## Clés de projets Malt connues

Chercher dans les fichiers `sonar-project.properties` du repo :
```bash
find . -name "sonar-project.properties" -exec grep "sonar.projectKey" {} \; -print
```

Format habituel : `com.malt.<module-name>` ou `malt-<module>`

## Limitations

- Auth via token personnel uniquement (pas OAuth navigateur)
- Docker doit être running localement
- `--pull=always` : télécharge la dernière image à chaque démarrage (peut être lent)
