"""Tarea CCI que aprovisiona la biblioteca de clausulas CLM de la demo COMEXI.

El trabajo real lo hace scripts/comexi/provision_clm_clauses.py, que tambien se
puede ejecutar a mano durante el desarrollo. Aqui solo se resuelve la org del
keychain y se invoca el script, porque la tarea Command de CCI no sabe pasar la
org al comando.
"""

import subprocess
import sys
from pathlib import Path

try:
    from cumulusci.core.tasks import BaseTask
    from cumulusci.core.exceptions import CommandException
except ImportError:  # permite importar el modulo sin CCI instalado
    BaseTask = object
    CommandException = Exception

SCRIPT = "scripts/comexi/provision_clm_clauses.py"


class ProvisionComexiClmClauses(BaseTask):
    task_options = {
        "dry_run": {
            "description": "Muestra lo que crearia sin escribir nada en la org.",
            "required": False,
        },
    }

    def _run_task(self):
        repo_root = Path(self.project_config.repo_root)
        script = repo_root / SCRIPT
        if not script.exists():
            raise CommandException(f"No encuentro {SCRIPT} en {repo_root}.")

        # El script habla con la org via sf CLI, asi que necesita el username, no el
        # alias de CCI: org_config.name devuelve el alias de CCI, que el CLI no conoce.
        cmd = [sys.executable, str(script), "--org", self.org_config.username]
        if str(self.options.get("dry_run", "")).lower() in ("true", "1", "yes"):
            cmd.append("--dry-run")

        self.logger.info(f"Aprovisionando clausulas CLM en {self.org_config.username}")
        result = subprocess.run(cmd, cwd=str(repo_root))
        if result.returncode != 0:
            raise CommandException(
                f"{SCRIPT} termino con codigo {result.returncode}. "
                "Revisa que ClauseCatgConfiguration COMEXI_Retrofit este desplegada."
            )
