# 05 · Documento, Contrato y Firma (Document Generation + CLM)

> Sustituye el menú `COMEXI Launcher → Generar Oferta` (Google Docs multiidioma), el versionado manual del vendedor y el "contrato de viabilidad" duplicado al 99% de la oferta.
>
> **Escenas:** 9 (documento de oferta + versión 2), 10 (contrato + firma).
> **Referencia:** bundle `unpackaged/post_docgen` (4 `documentTemplates`, `documentGenerationSettings`, `omniDataTransforms`), plan `qb-clm`, flow `RLM_Order_Contract_Creation_and_Association`, clase `RLM_OrderItemContractingUtility`.

## 1. DocumentTemplate — `COMEXI_RetrofitOffer`

Reproduce el documento de oferta observado (Ref. 46:50–50:45), con las secciones que ya usan. Clonar la estructura de `RLM_QuoteProposal_1.dt` de `post_docgen`.

| Campo | Valor | Nota |
| :-- | :-- | :-- |
| `Name` | `COMEXI_RetrofitOffer` | alfanumérico, sin espacios |
| `Type` | `Microsoft365Word` | |
| `UsageType` | `Contract_Lifecycle_Management` | |
| `TokenMappingType` | `JSON` | |
| `TokenMappingMethodType` | `ContextService` | |
| `ContextDefinitionName` | `RLM_SalesTransactionContext` | datos vivos de la Quote |
| `ContextMappingName` | `QuoteEntitiesMapping` | |
| `TargetTokenObject` | `Quote` | (multipicklist: Quote) |
| **`DocumentGenerationMechanism`** | **`ServerSide`** | crítico: el default `ClientSide` hace fallar el botón Generate con "Document was not generated" |
| `Status` / `IsActive` | Active / true | activar con `activateDocgenTemplates.apex` |

`DocumentTemplateContentDoc`: **uno solo** por template (el .docx base).

### Secciones del documento (replican la oferta actual, Ref. 46:50)

1. Identificación de la máquina (Asset, modelo, cliente)
2. Precio total y exclusiones a cargo del comprador
3. Alcance del upgrade (retrofit + opcionales configurados)
4. Instalación y puesta en marcha (líneas de intervención)
5. Pruebas
6. Plazo de entrega
7. Condiciones de pago (incl. down payment)
8. Garantía (uplift 2,60%, 6 meses desde aceptación)
9. Confidencialidad
10. Fotos según lo que se vende (Ref. 45:01)

## 2. Multiidioma (7 idiomas)

El cliente tiene textos fijos pretraducidos a 7 idiomas; el idioma se asigna por país, con mapeo manual de excepciones (Argelia → francés) (Ref. 45:01–45:44).

Modelo: cláusulas por idioma vía `DocumentClauseSet` (uno por `Category × DefaultLanguage`) + `DocumentClause`. `DefaultLanguage` es **obligatorio de facto** (la UI oculta los sets sin idioma).

| Objeto | Config |
| :-- | :-- |
| `ClauseCatgConfiguration` | categorías: `Precio`, `Garantia`, `Pago`, `Confidencialidad`, `Instalacion` |
| `DocumentClauseSet` | uno por (categoría × idioma). `DefaultLanguage` ∈ {es, en, fr, de, it, pt, ...} — los 7 del cliente |
| `DocumentClause` | `Content` (no `ClauseBody`), `Format` = `Rich_Text`, `Status` = `Draft` al crear, `Language` |

> **Category referencia con ID de 15 chars:** `DocumentClauseSet.Category` es un picklist restringido cuyos valores son IDs de `ClauseCatgConfiguration` de 15 caracteres. Cargar en orden: `ClauseCatgConfiguration` → `DocumentClauseSet` → `DocumentClause`.

La **asignación de idioma por país** (con el mapeo de excepciones) se implementa como flow/lógica que setea el idioma del documento a partir de `Account.BillingCountry` — replicando su mapa actual.

## 3. Associated Clauses: DocumentAuthoredContent

La pestaña "Associated Clauses" **no lee de `DocumentTemplateSection`**, lee de `DocumentAuthoredContent`. Una fila por cláusula asociada al template:

| Campo | Valor |
| :-- | :-- |
| `ReferenceObjectId` | ID del `DocumentTemplate` `COMEXI_RetrofitOffer` |
| `ReferenceObjectRecordType` | `DocumentTemplate` |
| `ContentType` | `StandardDocumentClause` |
| `StandardContentObjectType` | `DocumentClause` |
| `StandardContentObjectId` | ID del `DocumentClause` correspondiente |
| `ContentGenerationSource` | `StandardContent` |
| `IsReviewed` / `IsLibraryAdditionRequested` | false / false |

## 4. Versionado (escena 9)

El versionado es automático en RLM: si el cliente pide un cambio, se ajusta la Quote y se regenera el documento; el número de versión y el histórico salen del versionado de Quote, no de teclear a mano (contraste con Ref. 46:17, doc compartido con 189 personas). El control de acceso pasa a permisos por perfil, no a compartición de ficheros.

## 5. Contrato (escena 10): createContract

El contrato nace de la Quote aceptada — **no** un segundo documento (elimina el "contrato de viabilidad" duplicado, dolor **D7**).

```
POST /services/data/v66.0/actions/standard/createContract
{
  "inputs": [{
    "sourceId": "<QuoteId>",
    "contractPriceOption": "CONTRACT_HEADER_ONLY"
  }]
}
```

- `contractPriceOption`: `CONTRACT_HEADER_ONLY` (por defecto), `NET_UNIT_PRICE_ONLY` o `DISCOUNT_ONLY`. Para retrofit con precio negociado, evaluar `NET_UNIT_PRICE_ONLY`.
- Output: `contractId`.
- Reutilizar el flow `RLM_Order_Contract_Creation_and_Association` y `RLM_OrderItemContractingUtility`.

> **Precaución `ContextUseCaseMapping`:** los mappings estándar (`OppToCntr*`, `OrderToCntr*`) llegan con `TargetObjectRecordTypeId` nulo, lo que rompe "Create Contract" si el objeto `Contract` tiene RecordTypes activos. Revisar antes de la demo.

El documento contractual se genera con el mismo motor de Document Generation (`UsageType = Contract_Lifecycle_Management`), reutilizando las cláusulas por idioma.

## 6. Firma electrónica — GAP declarado

**No hay firma electrónica nativa confirmada** en las skills de Revenue Cloud v66.0. Lo más cercano son los objetos `DocumentEnvelope`, `DocumentRecipient`, `GeneratedDocument`, `GeneratedDocumentSection`, que aparecen como nombres en la lista de Advanced Approvals **sin documentación de campos ni flujo de firma**.

Opciones para la demo (a decidir con el cliente):

| Opción | Descripción | Estado |
| :-- | :-- | :-- |
| A | Firma con solución nativa `DocumentEnvelope`/`DocumentRecipient` si la org la tiene activa | a validar en la org |
| B | Integración con firma externa (DocuSign/Adobe) vía AppExchange | fuera de "100% nativo" |
| C | Simular el paso de firma en la demo (estado del contrato → "Firmado") sin proveedor real | recomendada para la demo |

Recomendación: **Opción C** para la demo comprometida (el foco de la escena 10 es *eliminar el documento duplicado*, no la firma en sí), y dejar A/B como decisión de proyecto.

## 7. Despliegue y verificación

1. Reutilizar `prepare_docgen` / `deploy_post_docgen` como base y añadir `COMEXI_RetrofitOffer`.
2. Cargar cláusulas con el plan `comexi-clm` (patrón `qb-clm`).
3. `activateDocgenTemplates.apex`.
4. Verificar: generar la oferta del caso 174535 en español y en inglés; regenerar tras un cambio → versión 2 con histórico; `createContract` desde la Quote aceptada → contrato con cláusulas.
