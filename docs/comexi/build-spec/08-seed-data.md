# 08 · Seed Data (datos de arranque de la demo)

> Datos preconfigurados para arrancar la demo con el caso real. Todos los valores provienen del Canvas de Discovery (leídos de pantalla o citados en la sesión).
>
> **Plan SFDMU:** `comexi-seed` (Account, Contact, Asset, Case). La **Quote inicial** NO se carga por SFDMU (rompería el pricing): se genera con `PlaceQuote` en un script Apex/harness.
> **Referencia:** plan `qb/scratch_data` (Account/Contact/BillingAccount), harness `scripts/txn_data_harness/`, `scripts/build_quote_to_asset.py`.

## 1. Account y Contacts

### Account — Roberts Mart Co Ltd

| Campo | Valor |
| :-- | :-- |
| `Name` | Roberts Mart Co Ltd |
| `BillingCity` | Leeds |
| `BillingCountry` | United Kingdom |
| `COMEXI_Has_Representative__c` | true |
| `COMEXI_Representative_Commission_Pct__c` | 8 |

> `COMEXI_Has_Representative__c = true` es lo que hace que el pricing procedure aplique la comisión del 8% (paso 5 del escandallo). Sin representante, el paso no aplica.

### Contacts

| Name | Rol | Campo |
| :-- | :-- | :-- |
| David Prieto | Service Manager | referenciado en el filtro del Launcher (Ref. 8:38) |
| Ramón Cabrales | Responsable de configuración | autor del proceso, sponsor de la demo |

## 2. Base instalada (Asset)

### Máquina principal — MSC000600 (viable)

| Campo | Valor |
| :-- | :-- |
| `Name` / serial | MSC000600 |
| `Product2` | Comexi Proslit S2 DS |
| `Account` | Roberts Mart Co Ltd |
| `COMEXI_Machine_Model__c` | Proslit S2 DS |
| `COMEXI_Line__c` | T |
| `COMEXI_Install_Year__c` | (año que la haga viable para T100, p. ej. 2015) |
| `COMEXI_Installed_Config__c` | PC con Windows XP/10, CPU GL, CU, pantalla |

Assets hijos (componentes): PC (Windows obsoleto), CPU GL, CU, pantalla — para la jerarquía de [`07-assets-agentforce-dashboards.md`](07-assets-agentforce-dashboards.md) §1.

### Segunda máquina — antigua (no viable sin ingeniería)

| Campo | Valor |
| :-- | :-- |
| `Name` / serial | (p. ej. MSC000123) |
| `COMEXI_Machine_Model__c` | modelo de los años 90/2000 |
| `COMEXI_Install_Year__c` | 2001 (antigüedad alta → coste x3/x4) |

Propósito: demostrar que el T100 **no se cualifica** sobre ella → veredicto del agente "requiere ingeniería" (escena 2, contraste de viabilidad).

## 3. Case inicial — 174535

| Campo | Valor |
| :-- | :-- |
| `CaseNumber` (o campo de referencia) | 174535 |
| `Asset` | MSC000600 |
| `Subject` | PC + Win |
| `Description` | Actualitzem oferta W11 si us plau |
| `Account` | Roberts Mart Co Ltd |
| Owner | (Case Owner del filtro del Launcher) |

> El caso se abre **sobre el Asset** (en servicio los casos cuelgan de la máquina, Ref. 8:38). Es el punto de partida de la escena 1.

## 4. Cotización inicial (Quote) — vía PlaceQuote, no SFDMU

Para arrancar la demo con una cotización ya montada (o para tests), generar con `PlaceQuote` (ver [`04-quote-margen-aprobaciones.md`](04-quote-margen-aprobaciones.md) §3). Nunca DML directo.

Estructura del caso 174535:

| Grupo | Líneas |
| :-- | :-- |
| Producto | T100 (bundle, con W11 + opcionales configurados) + T100-TEMP (3.600 €) |
| Intervención | SRV-MEC, SRV-ELE, SRV-PME (horas del caso) |
| Gastos | EXP-FLIGHT, EXP-TAXI, EXP-HOTEL, EXP-MEAL (total 2.420 €, `Charged_To` según negociación) |

## 5. Cifras de calibración (deben reproducirse)

La demo es creíble solo si los números coinciden con los que Comexi vio en su hoja:

| Métrica | Objetivo |
| :-- | :-- |
| Coste resultante | 4.923,49 € |
| Precio de venta (margen 42%) | 7.321,39 € |
| Precio final (−5%) | **6.955,32 €** |
| Margen resultante | **27,54%** |
| Total desplazamientos | 2.420,00 € |
| Add-on tinta | 3.600,00 € |

Ajustar `PricebookEntry.UnitPrice` y `CostBookEntry.Cost` ([`02-pricing-escandallo.md`](02-pricing-escandallo.md)) hasta que la waterfall del T100 con 5% de descuento dé estos valores.

## 6. export.json (comexi-seed)

- Objetos y orden: `Account` → `Contact` → `Asset` (raíz antes que hijos, usar `ParentId`/`RootAssetId`) → `Case`.
- `externalId`:
  - `Account` → `Name`
  - `Contact` → `Email` o `LastName;AccountId.Name`
  - `Asset` → `SerialNumber` o `Name`
  - `Case` → campo de referencia con `174535`
- Marcar CSVs vacíos con `excluded: true`.

## 7. Verificación

- Tras cargar `comexi-seed`: el Asset MSC000600 existe con jerarquía y el Case 174535 cuelga de él.
- Ejecutar el script de `PlaceQuote` → Quote sin banner naranja, con los tres grupos y las cifras calibradas.
- La segunda máquina antigua existe y no cualifica para T100.
