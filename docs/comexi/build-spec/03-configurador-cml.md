# 03 · Configurador y CML

> Sustituye las pestañas `ETO_Options`/`ETO_Codes` (preguntas y opcionales por producto) y el filtro de viabilidad que hoy hace ingeniería manualmente sobre datos dispersos (SAP + PLM + Excels).
>
> **Escenas:** 4 (el vendedor configura solo, reglas en tiempo real), 2 (viabilidad contra el Asset).
> **Modelo:** `scripts/cml/COMEXI_T100.cml`. **Planes SFDMU:** `comexi-constraints-p`, `comexi-constraints-prc`. **Referencia:** `datasets/constraints/mfg/genSet/`, flow `prepare_constraints`, task `import_cml` (`tasks.rlm_cml.ImportCML`).

## 0. Correcciones de sintaxis CML (crítico)

CML v3.2 **no** tiene `implies`, `requires` ni `excludes`. Usa:

- Operador de implicación `->`
- Reglas `require(...)`, `exclude(...)`, `message(...)`, `constraint(...)`
- Proxy `cardinality(<type>, <relation>)` para contar instancias
- Un constraint model **es un `ExpressionSet`**; se despliega como `ExpressionSetDefinition` + `ExpressionSetDefinitionVersion`. No hay tipo de metadata "ConstraintModel".
- Asociación al producto vía **`ExpressionSetConstraintObj`** (`ConstraintModelTag`, `ConstraintModelTagType` ∈ {`Type`, `Port`}).
- Para poner un constraint sobre un child de un bundle, el bundle completo debe estar en el modelo.

## 1. Modelo `COMEXI_T100.cml`

Reproduce las preguntas (nº CPUs, nº CUs) y opcionales del T100, con las reglas que impiden combinaciones imposibles. Ejemplo de estructura (ajustar valores a la lógica real cuando el cliente la confirme):

```cml
// COMEXI_T100.cml — Retrofit T100 UPDATE PC
// Sustituye ETO_Options / ETO_Codes del LAUNCHER V8.4

model COMEXI_T100 {

  // --- Preguntas de configuración (atributos del producto) ---
  extern int numCpuGL;        // COMEXI_Num_CPU_GL
  extern int numCuTotal;      // COMEXI_Num_CU_Total

  // --- Tipos de componente (mapean a Product2 del bundle) ---
  type UpdateBase           "T100-W11";        // requerido siempre
  type CpuSimotion          "T100-CPU-SIM";
  type CuSinamics           "T100-CU-SIN";
  type PupitreHMI           "T100-HMI";
  type CanviPantalla        "T100-SCREEN";
  type ChecklistSerie       "T100-CHECKLIST";

  // --- Relaciones (estructura del bundle) ---
  relation Core    : UpdateBase[1..1];        // el update W11 es obligatorio
  relation Options : (CpuSimotion | CuSinamics | PupitreHMI | CanviPantalla | ChecklistSerie)[0..5];

  // --- Reglas ---

  // 1. El update base siempre presente
  require(true, Core[UpdateBase] == 1,
    "El retrofit T100 incluye siempre la actualización a Windows 11.");

  // 2. Si hay CPUs GL declaradas, se necesita el cambio de CPU Simotion
  constraint(numCpuGL > 0 -> cardinality(CpuSimotion, Options) >= 1,
    "Con CPUs GL en la máquina, el cambio de CPU Simotion es obligatorio.");

  // 3. Si hay CUs, se necesita el cambio de CU Sinamics
  constraint(numCuTotal > 0 -> cardinality(CuSinamics, Options) >= 1,
    "Con CUs en la máquina, el cambio de CU Sinamics es obligatorio.");

  // 4. El pupitre HMI y el cambio de pantalla son mutuamente excluyentes
  constraint(cardinality(PupitreHMI, Options) + cardinality(CanviPantalla, Options) <= 1,
    "Pupitre HMI y cambio de pantalla no pueden ir en el mismo retrofit.");

  // 5. Aviso informativo cuando se pide checklist con nº de serie
  message(cardinality(ChecklistSerie, Options) >= 1,
    "Recuerda adjuntar los números de serie de los componentes sustituidos.",
    Info);
}
```

> Los valores concretos de las reglas (qué exige qué) deben validarse con Comexi; el Discovery confirma la *existencia* de preguntas y opcionales y que "el vendedor hoy no sabe responderlas" (Ref. 34:55), pero no la matriz de compatibilidad exacta. Marcar como supuesto a validar.

## 2. Asociación al producto: ExpressionSetConstraintObj

Dos planes SFDMU separados por tipo de asociación (patrón `mfg-constraints-p` / `mfg-constraints-prc`):

### `comexi-constraints-p` — tipo `Type` (producto ↔ modelo)

| ExpressionSet | ProductId (SKU) | ConstraintModelTag | ConstraintModelTagType |
| :-- | :-- | :-- | :-- |
| `COMEXI_T100` | `T100` | `COMEXI_T100` | `Type` |

### `comexi-constraints-prc` — tipo `Port` (componente ↔ modelo)

Una fila por componente del bundle que participa en reglas:

| ExpressionSet | ProductId (SKU) | ConstraintModelTag | ConstraintModelTagType |
| :-- | :-- | :-- | :-- |
| `COMEXI_T100` | `T100-CPU-SIM` | `CpuSimotion` | `Port` |
| `COMEXI_T100` | `T100-CU-SIN` | `CuSinamics` | `Port` |
| `COMEXI_T100` | `T100-HMI` | `PupitreHMI` | `Port` |
| `COMEXI_T100` | `T100-SCREEN` | `CanviPantalla` | `Port` |
| `COMEXI_T100` | `T100-CHECKLIST` | `ChecklistSerie` | `Port` |
| `COMEXI_T100` | `T100-W11` | `UpdateBase` | `Port` |

## 3. Despliegue (reutiliza `prepare_constraints`)

Orden obligatorio: **catálogo (PCM) → `ExpressionSetConstraintObj` → reglas**. CML referencia SKUs del catálogo, así que el catálogo va primero.

Secuencia (patrón del flow existente `prepare_constraints`):

1. `insert_comexi_transactionprocessingtypes_data` (si aplica) o reutilizar el de qb.
2. `deploy_post_constraints` (bundle `unpackaged/post_constraints` — reutilizable).
3. `enable_constraints_settings`.
4. `validate_cml` sobre `scripts/cml/COMEXI_T100.cml` (`tasks.rlm_cml.ValidateCML`).
5. `import_cml` (`tasks.rlm_cml.ImportCML`) — importa el modelo como `ExpressionSetDefinition`.
6. `insert_comexi_constraints_p_data` + `insert_comexi_constraints_prc_data` (asociaciones).
7. `manage_expression_sets` — desactivar versiones previas, activar la nueva (regla: no se puede actualizar un ExpressionSet activo).

## 4. Cualificación de viabilidad (escena 2)

La "viabilidad" (¿el retrofit estándar encaja en esta máquina de posiblemente 23 años?) se modela en dos capas:

### Capa 1 — ProductQualification contra el Asset

Reutiliza la decision table `RLM_ProductQualification` (ya en el repo, `unpackaged/pre/5_decisiontables/`) y la task `refresh_dt_asset`. Regla: el T100 solo se cualifica si el Asset tiene los componentes/atributos compatibles.

| Objeto | Uso |
| :-- | :-- |
| `ProductQualification` | condiciona la visibilidad/elegibilidad del T100 según contexto del Asset |
| Decision table `RLM_ProductQualification` | inputs: modelo de máquina, antigüedad, componentes instalados → output: cualifica sí/no |

Campos de Asset que alimentan la cualificación (ver [`07-assets-agentforce-dashboards.md`](07-assets-agentforce-dashboards.md)):

- `COMEXI_Machine_Model__c` (p. ej. "Proslit S2 DS")
- `COMEXI_Install_Year__c` (antigüedad → multiplicador de coste x3/x4 en máquinas antiguas, Ref. 31:16)
- `COMEXI_Installed_Config__c` (componentes: CPU, CU, versión de Windows)

### Capa 2 — Agentforce razona sobre la cualificación

El agente `COMEXI_Retrofit_Advisor` (ver documento 07) lee el resultado de la cualificación + el texto del caso y produce el **veredicto con el porqué**: qué componentes de esa máquina lo permiten y qué la haría requerir ingeniería. La decision table da el dato; el agente da la explicación con traza.

## 5. Verificación

- Log de Apex a nivel FINE, sección `RLM_CONFIGURATOR_STATS`: objetivo < 100 ms, < 1000 backtracks, 0 violaciones.
- En la UI: abrir el T100 en el configurador desde una Quote y comprobar que:
  - Las dos preguntas (CPU/CU) aparecen.
  - Seleccionar pupitre HMI + cambio de pantalla dispara el mensaje de exclusión (regla 4).
  - Con `numCpuGL > 0` sin Simotion, la config queda inválida (regla 2).
- Sobre la **segunda máquina antigua** del seed data: el T100 no se cualifica → veredicto "requiere ingeniería" (demuestra el filtro de viabilidad).
