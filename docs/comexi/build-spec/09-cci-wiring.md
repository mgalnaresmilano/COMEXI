# 09 · Cableado CumulusCI, Gaps y Riesgos

> Cómo se integra el shape `comexi` en `rlm-base-dev` siguiendo el patrón documentado en `datasets/sfdmu/mfg/README.md` §"Adding a new MFG plan".

## 0. Estado de la org `comexi`

Existe una org conectada y **no está vacía**: parte de una base RLM ya desplegada. Esto cambia la estrategia de build — se **superpone** el shape `comexi` sobre una base viva, no se construye de cero.

| Dato | Valor |
| :-- | :-- |
| Alias `sf` | `comexi` |
| Usuario | `trailsignup.998d55bf0e1b20@salesforce.com` |
| Instance | `https://trailsignup-998d55bf0e1b20.my.salesforce.com` |
| Estado | Connected · API v67.0 |
| Tipo | org no-scratch (registrada en `sf`, no como scratch de CCI) |

Inventario observado (query directa):

| Objeto | Registros | Lectura |
| :-- | :-- | :-- |
| `ProductCatalog` | 3 | RLM PCM ya desplegado |
| `Product2` | 314 | catálogo cargado (probablemente shape `qb`) |
| `ExpressionSet` | 15 | pricing procedures + constraint models presentes |
| `ExpressionSetConstraintObj` | 211 | configurador ya cableado |
| `DocumentTemplate` | 20 | Document Generation activo |
| `PriceAdjustmentSchedule` | 3 | pricing con adjustments |
| `Asset` | **0** | **base instalada vacía → hay que sembrarla** |

Implicaciones para el build:

- **No re-ejecutar `prepare_rlm_org` completo** sobre esta org: la base RLM (contextos, pricing procedures, docgen, constraints engine, billing/dro) ya existe. Verificar y reutilizar.
- **Conectar la org a CCI** para poder correr las tasks/flows: `cci org import comexi comexi` (importa la org `sf` con nombre CCI `comexi`), o trabajar con `sf`/Metadata API directamente usando `--target-org comexi`.
- **Convivencia con el catálogo existente:** los 314 `Product2` son probablemente QuantumBit. El catálogo Comexi se añade en su propio `ProductCatalog` (`COMEXI_SERVICE`) sin borrar el existente. Confirmar SKUs para evitar colisiones de `StockKeepingUnit`.
- **Sembrar la base instalada:** 0 Assets → el plan `comexi-seed` ([`08-seed-data.md`](08-seed-data.md)) es imprescindible para las escenas 1, 2, 12, 14.
- **Antes de construir:** hacer un describe de los objetos y de los campos custom `COMEXI_*` para no redeclarar lo que ya exista, y revisar qué flow de `rlm-base-dev` se corrió (ver `stamp_git_commit` / metadata desplegada).

## 1. Feature flag

En `cumulusci.yml`, sección `project: custom:` (~L85-145), añadir:

```yaml
    # Comexi Retrofit Demo
    comexi: True
    product_dataset: comexi   # (opcional) si se usa comexi en lugar de qb como shape principal
```

> Decisión: el shape `comexi` puede convivir con `qb` (gating por flag) o sustituirlo como `product_dataset`. Para una demo dedicada a Comexi, lo más limpio es un flow propio `prepare_comexi_demo` que se ejecuta en una org preparada, sin mezclar con el catálogo QuantumBit.

## 2. Anchors de datasets

Junto a los anchors existentes (`cumulusci.yml` ~L602-635):

```yaml
    comexi_pcm_dataset: &comexi_pcm_dataset datasets/sfdmu/comexi/en-US/comexi-pcm
    comexi_pricing_dataset: &comexi_pricing_dataset datasets/sfdmu/comexi/en-US/comexi-pricing
    comexi_constraints_p_dataset: &comexi_constraints_p_dataset datasets/sfdmu/comexi/en-US/comexi-constraints-p
    comexi_constraints_prc_dataset: &comexi_constraints_prc_dataset datasets/sfdmu/comexi/en-US/comexi-constraints-prc
    comexi_clm_dataset: &comexi_clm_dataset datasets/sfdmu/comexi/en-US/comexi-clm
    comexi_dro_dataset: &comexi_dro_dataset datasets/sfdmu/comexi/en-US/comexi-dro
    comexi_seed_dataset: &comexi_seed_dataset datasets/sfdmu/comexi/en-US/comexi-seed
```

CML source: `scripts/cml/COMEXI_T100.cml`.

## 3. Tasks

Por cada plan, tres tasks (patrón `tasks.rlm_sfdmu.*`), todas con `group: Revenue Lifecycle Management` o el grupo que corresponda:

```yaml
tasks:
  insert_comexi_pcm_data:
    group: Revenue Lifecycle Management
    description: >
      Carga el catálogo de retrofit Comexi (ProductCatalog, ProductCategory,
      ProductClassification, Product2, atributos y bundle T100).
    class_path: tasks.rlm_sfdmu.LoadSFDMUData
    options:
      pathtoexportjson: *comexi_pcm_dataset

  insert_comexi_pricing_data:
    group: Revenue Lifecycle Management
    description: Carga cost book, price book y adjustment schedules del escandallo Comexi.
    class_path: tasks.rlm_sfdmu.LoadSFDMUData
    options:
      pathtoexportjson: *comexi_pricing_dataset

  # ... comexi_constraints_p, comexi_constraints_prc, comexi_clm, comexi_dro, comexi_seed
```

Añadir también, por plan, las tasks `extract_comexi_<dominio>_data` (`tasks.rlm_sfdmu.ExtractSFDMUData`, grupo `Data Management - Extract`) y `test_comexi_<dominio>_idempotency` (`tasks.rlm_sfdmu.TestSFDMUIdempotency`, grupo `Data Management - Idempotency`).

## 4. Flow `prepare_comexi_demo`

Orquesta la construcción respetando el orden de dependencias (PCM → pricing → expression sets → constraints → CLM → DRO → seed):

```yaml
flows:
  prepare_comexi_demo:
    group: Revenue Lifecycle Management
    description: Prepara el entorno de demo de retrofit Comexi sobre una org RLM base.
    steps:
      1:
        task: insert_comexi_pcm_data
      2:
        task: insert_comexi_pricing_data
      3:
        task: activate_and_deploy_expression_sets   # incluye COMEXI_RetrofitPricingProcedure
      4:
        flow: prepare_constraints                     # reutiliza validate_cml/import_cml; añadir comexi-constraints-*
      5:
        task: insert_comexi_constraints_p_data
      6:
        task: insert_comexi_constraints_prc_data
      7:
        task: insert_comexi_clm_data
      8:
        task: insert_comexi_dro_data
      9:
        task: refresh_dt_asset
      10:
        task: insert_comexi_seed_data
      11:
        task: refresh_all_decision_tables
```

> El pricing procedure `COMEXI_RetrofitPricingProcedure` (ExpressionSetDefinition en `force-app`) se despliega con `deploy_full` / `activate_and_deploy_expression_sets`. Las decision tables `COMEXI_*` se despliegan como metadata y se refrescan en los pasos 9/11.

### Punto de inserción en `prepare_rlm_org`

Dos opciones:

- **A (recomendada para demo dedicada):** ejecutar `prepare_rlm_org` estándar (que deja la org RLM base con billing, dro, clm, agents, docgen, constraints activos) y después `cci flow run prepare_comexi_demo`.
- **B (integrado):** añadir un paso `prepare_comexi_demo` al final de `prepare_rlm_org`, gated `when: project_config.project__custom__comexi`, tras `prepare_constraints` y antes de `refresh_all_decision_tables`.

## 5. Reutilizables (no reconstruir)

| Pieza | Ruta / nombre | Para |
| :-- | :-- | :-- |
| Contextos | `RLM_AssetContext`, `RLM_FulfillmentAssetContext`, `RLM_SalesTransactionContext` | pricing, assets, DRO |
| Flows assetización | `RLM_Assetize_Order`, `RLM_Set_Asset_Parent_From_Relationship`, `RLM_CreateOrdersFromQuote`, `RLM_Order_Contract_Creation_and_Association` | escenas 10, 11, 12 |
| Bundle constraints | `unpackaged/post_constraints` | configurador |
| Bundle docgen | `unpackaged/post_docgen` | documento |
| Bundle approvals | `unpackaged/post_approvals` | aprobación |
| Bundle agents | `unpackaged/post_agents` | Agentforce NGA |
| Decision tables | `RLM_ProductQualification`, `RLM_CostBookEntries` | viabilidad, coste |
| Tasks CML | `validate_cml`, `import_cml` (`tasks.rlm_cml.*`) | despliegue CML |
| Tasks pricing | `activate_and_deploy_expression_sets`, `configure_pricing_recipe_table_mappings`, `refresh_dt_*` | pricing procedure |
| Clases | `RLM_PlaceQuoteModel`, `RLM_PlaceOrderModel`, `RLM_AssetInfoUtility`, `RLM_OrderItemContractingUtility`, `DFOApexMockService` | Quote, Order, Asset, contrato, mock SAP |
| Harness | `scripts/txn_data_harness/`, `scripts/build_quote_to_asset.py` | generar Quote/Order/Asset sin DML |

## 6. Metadata nueva a crear en `force-app`

| Tipo | Elemento |
| :-- | :-- |
| `expressionSetDefinition` | `COMEXI_RetrofitPricingProcedure` |
| `decisionTables` (unpackaged/pre) | `COMEXI_Warranty_Uplift`, `COMEXI_RALF_Uplift`, `COMEXI_Risk_Matrix`, `COMEXI_Rep_Commission` |
| Campos custom | `QuoteLineItem.COMEXI_Cost__c`, `COMEXI_Margin_Pct__c`, `COMEXI_Target_Margin_Pct__c`; `Quote.COMEXI_Total_Cost__c`, `COMEXI_Blended_Margin_Pct__c`, `COMEXI_Discount_Pct__c`; `Product2.COMEXI_Target_Margin_Pct__c`; `Asset.COMEXI_Machine_Model__c`, `COMEXI_Install_Year__c`, `COMEXI_Installed_Config__c`, `COMEXI_Line__c`; `Account.COMEXI_Has_Representative__c`, `COMEXI_Representative_Commission_Pct__c` |
| `documentTemplates` | `COMEXI_RetrofitOffer` |
| Record types Opportunity | `COMEXI_Comercial`, `COMEXI_Retrofitting`, `COMEXI_Servicio` |
| `aiAuthoringBundles` | `COMEXI_Retrofit_Advisor` (NGA) |
| Reports / Dashboards | dashboard de ofertas y pedidos |
| CML | `scripts/cml/COMEXI_T100.cml` |

## 7. Validación del cableado

- `cci task list` muestra las tasks `insert_comexi_*`.
- `cci flow run prepare_comexi_demo --org <org>` completa sin error.
- `python scripts/validate_sfdmu_v5_datasets.py` sobre cada plan `comexi-*`.
- Tests de idempotencia `test_comexi_*_idempotency`.
- Regenerar referencia CCI: `python scripts/ai/generate_cci_reference.py`.
- Añadir un `README.md` por plan bajo `datasets/sfdmu/comexi/` (patrón `qb-pcm/README.md`).

## 8. Gaps del Discovery (arrastrados como preguntas abiertas)

| # | Gap | Impacto en la construcción |
| :-- | :-- | :-- |
| 1 | Roles y aprobaciones tras el 1 sep 2026 | define el aprobador del approval (doc 04) y los perfiles de la demo |
| 2 | Volumen anual de ofertas y tasa de conversión | calibra los KPIs del dashboard (doc 07) |
| 3 | Nº medio de versiones por oferta y % renegociado | dimensiona el valor del versionado (doc 05) |
| 4 | Integración SAP actual (middleware, mantenedor) | condiciona el alcance real de la descomposición (doc 06) — en demo va con mock |
| 5 | Multidivisa | afecta al price book (doc 02) |
| 6 | Packs de servicio gold/silver | hoy sin catalogar; extensión del catálogo (doc 01) |
| 7 | Guardrails de seguridad de IA | argumento Trust Layer (doc 07); quedó sin responder en sesión |
| 8 | Licencias Salesforce actuales + fallo de artículos de conocimiento | condiciona el discurso "pasito a pasito" antes de proponer agéntica |
| 9 | Catálogo completo (113 productos) | requiere extract del Sheets del cliente; la demo usa los observados |

## 9. Riesgos

| Riesgo | Mitigación |
| :-- | :-- |
| **La org `comexi` ya tiene RLM + catálogo (qb) cargado** | no re-ejecutar `prepare_rlm_org`; superponer el shape `comexi` en su propio `ProductCatalog`; verificar colisiones de `StockKeepingUnit` y campos `COMEXI_*` antes de desplegar |
| Org conectada solo en `sf`, no en CCI | `cci org import comexi comexi` antes de correr tasks/flows |
| Firma electrónica nativa sin confirmar | opción C (simular) para la demo; decisión de proyecto (doc 05) |
| Matriz de compatibilidad CML no confirmada por el cliente | las reglas de `COMEXI_T100.cml` son supuestos a validar (doc 03) |
| El motor de pricing no tiene paso de margen | margen expuesto en campos custom, no en el procedure (doc 02) |
| Banner naranja si se hace DML sobre Quote | usar siempre `PlaceQuote` (doc 04, 08) |
| Catálogo poblado a mano puede no cuadrar con precios reales | calibrar solo con las cifras del caso 174535; no inventar precios de otros productos |
