# Demo Script & Build Specification — Comexi · Salesforce Revenue Cloud

> **Fuente:** Canvas de Discovery `comexi-discovery-revenue-cloud.canvas.tsx`, derivado de la sesión *Comexi | Salesforce — Reverse Demo* del 4 ago 2026 (1:16:20). 916 fotogramas a 5 s cruzados con la transcripción con marcas de tiempo.
>
> **Objetivo de este documento:** servir a la vez de (a) guión narrativo y comercial de la demo y (b) especificación funcional/técnica que Cursor consume para construir el entorno. El detalle ejecutable por dominio vive en [`build-spec/`](build-spec/00-README.md).
>
> **Stack objetivo:** Revenue Cloud / Revenue Lifecycle Management (RLM) **100% nativo**, API **v66.0** (Spring '26), sobre el repositorio `rlm-base-dev`.

---

## 1. Ficha Técnica y Objetivos de la Demo

### Cliente / Caso de Uso

**Comexi** (Girona) — fabricante de maquinaria de impresión flexográfica y *converting*. La demo se centra en su **negocio de Servicio y Retrofit**: paquetes estandarizados que se venden sobre máquinas ya instaladas en la base de clientes (algunas de los años 90 y principios de los 2000).

El hilo narrativo es un **caso real observado en la sesión**:

| Dato | Valor |
| :--- | :--- |
| Caso Salesforce | **174535** |
| Cliente | **Roberts Mart Co Ltd** (Leeds, United Kingdom) |
| Máquina (Asset) | **MSC000600** — Comexi S2 DS (`MAQ-S2-DS`, antiguo Proslit S2 DS; línea T) |
| Retrofit | **T100 - UPDATE PC** (migración de PC con Windows XP/10 a Windows 11) |
| Add-on solicitado | Control de temperatura de la tinta (**+3.600 €**) |
| Coste resultante | 4.923,49 € |
| Precio de venta (margen 42%) | 7.321,39 € |
| Precio final (−5% descuento) | **6.955,32 €** |
| Margen resultante | **27,54%** |

### Objetivo Principal

Demostrar que Revenue Cloud **reemplaza por completo** el CPQ artesanal que Comexi ha construido en Google Sheets (`LAUNCHER - V8.4`, 12+ pestañas: catálogo, configurador, escandallo, planificador de intervención, generador de oferta multiidioma y log de pedidos) más los Google Docs de oferta y "contrato de viabilidad". No se trata de "sustituir un Excel": se trata de **reproducir su lógica de negocio con funcionalidad estándar** y ganar en lo que ellos hoy no pueden tener: trazabilidad, escala, gobierno del dato y capacidad agéntica sobre datos estructurados.

Frase que define la oportunidad (sesión, 1:05:08): *"Meter inteligencia artificial sobre un Excel es muy complicado, porque al final esto no va a estar conectando con todo el mundo que hay en el quote-to-cash."*

### Persona / Roles en la Demo

| Rol | Quién lo encarna | Qué representa |
| :--- | :--- | :--- |
| **Agente de servicio** | Soporte técnico | Recibe la incidencia y abre el caso sobre la máquina |
| **Agentforce** | Agente autónomo | Estudio de viabilidad y recomendación de producto (sustituye a `=GEMINI()`) |
| **Vendedor de servicio** | Comercial de retrofit | Configura, cotiza y negocia sin depender del back-office |
| **Manager / Director de servicio** | Aprobadores encadenados | Firman el descuento en la pestaña Approvals. En la org de demo los dos niveles recaen en el mismo usuario para no gastar licencias |
| **Legal** | Contratos | Genera y envía el contrato a firma |
| **Operaciones + Finanzas** | Back-office de pedido | Descompone el pedido a SAP y controla el down payment |
| **Dirección de servicio** | Sponsor | Consume dashboards y KPIs |

### Stack Salesforce Involucrado

- **Product Catalog Management (PCM)** — catálogo, categorías, clasificaciones, atributos, bundles.
- **Product Configurator + CML** — configuración guiada con reglas de restricción.
- **Salesforce Pricing** — price books, cost books, pricing procedures (Expression Sets), adjustment schedules.
- **Transaction Management** — Quote, QuoteLineGroup, Order.
- **Asset Lifecycle Management** — base instalada como fuente de viabilidad.
- **Contract Lifecycle Management (CLM)** — contrato desde la cotización + Document Generation.
- **Dynamic Revenue Orchestrator (DRO)** — descomposición a SAP y a operaciones.
- **Billing** — down payment como hito de facturación.
- **Agentforce (NGA / Agent Builder 2.0)** — viabilidad y oferta proactiva sobre la base instalada.
- **Reports & Dashboards** — visibilidad de ofertas, pedidos y márgenes.

---

## 2. Guión Detallado de la Demo (Demo Script)

Catorce escenas, ≈58 minutos, sobre un único hilo (caso 174535). En cada escena el objetivo es que Comexi **reconozca la pestaña de su hoja que acabamos de sustituir**. La columna de dolores usa los identificadores `D1`–`D13` del Canvas de Discovery (ver §4 y la pestaña *Dolores → Revenue Cloud* del canvas).

| # | Rol / Persona | Narrativa & Qué Decir (Dolores resueltos) | Acción en Pantalla (Salesforce) | Elemento "WOW" / Diferenciador |
| :-- | :-- | :-- | :-- | :-- |
| **01** | Agente de servicio | *"Hoy la máquina es una matrícula en una celda del Launcher (Ref. 6:26). Aquí es un objeto de primera clase: veis la configuración instalada, la antigüedad y el histórico."* Sobre el Asset ya hay un caso. **(D1, D8)** | Abrir **Asset** `MSC000600` → ver jerarquía de componentes → abrir el **Case** `174535` relacionado ("PC + Win, actualitzem oferta W11") | La base instalada es explotable, no un dato muerto en un Excel de hace 20 años |
| **02** | Agentforce | *"Esto es exactamente vuestra función `=GEMINI()` (Ref. 33:10), pero agéntica, con traza y sin poder inventarse un código. Vuestra prioridad nº 1."* **(D8, D2)** | Desde el Case, lanzar el agente **COMEXI Retrofit Advisor** → devuelve valoración + recomendación **T100 - UPDATE PC** + veredicto de viabilidad con el porqué. Mostrar que un código inexistente (P271, visto en 32:30) no se puede recomendar | El agente valida contra el catálogo real; nunca alucina un SKU. Trazabilidad completa de la recomendación |
| **03** | Vendedor de servicio | *"El modelo que ya estáis adoptando —el vendedor abre la oportunidad— pero sin trabajo manual y sin perder el vínculo con el caso (Ref. 14:54)."* **(D1, D10)** | Botón en el Case → **Opportunity** tipo *Retrofitting* (record type), asociada a Account, Asset y Case de origen. La ficha muestra secciones retrofit propias, pobladas solas: **Máquina** (asset, modelo, antigüedad, componente obsoleto), **Viabilidad** (veredicto, validado por el Advisor, confianza), **Alcance** (tipo de retrofit, SKU, semanas, anticipo) y **Económico** (coste, margen, si requiere aprobación). En *Activity* aparece copiado todo el historial del caso más la traza del Advisor | Un clic; oportunidad con datos custom del retrofit ya rellenos y la actividad del caso volcada en su timeline. Idempotente: relanzar no duplica oportunidad, oferta ni actividades |
| **04** | Vendedor de servicio | *"El 80% de retrofits no necesita ingeniería pero hoy el 100% pasa por tres personas (Ref. 27:13). Aquí el vendedor configura solo."* **(D2, D1)** | Crear **Quote** → **Configurador**: preguntas (nº CPUs GL, nº CUs) + opcionales (canvi CPU Simotion, CU Sinamics, pupitre HMI, canvi de pantalla). Una opción incompatible se bloquea con mensaje legible | Reglas de restricción CML en tiempo real; el cuello de botella del back-office desaparece |
| **05** | Vendedor de servicio | *"Vuestra pestaña de intervención (Ref. 35:57): horas, desplazamientos y estancia, con la palanca de 'a cargo de quién'."* **(D1, D4)** | Añadir a la Quote el **grupo Intervención**: horas de montaje mecánico, instalación eléctrica, puesta en marcha; y el **grupo Gastos** (vuelo, taxi, hotel, dietas para destino Leeds) con indicador Comexi/cliente | Su planificador de 6 semanas convertido en líneas de cotización con precio, coste y margen propios |
| **06** | Vendedor + Deal Desk | *"Vuestro escandallo (Ref. 39:40) no es código: es una procedura de precios configurable. Uplifts, riesgos y márgenes por concepto."* **(D1, D11)** | Ver el desglose: coste de material (cost book), horas al valor de Finanzas, uplift garantía **2,60%**, RALF **3,00%**, riesgo país/tecnología, comisión representante **8%**, márgenes por concepto **40 / 20 / 10** | El punto donde más miedo tienen a perder capacidad, reproducido sin una línea de Apex de negocio |
| **07** | Vendedor de servicio | *"Vuestra prioridad nº 2, literal (Ref. 59:18): 'este es el precio básico y el control de temperatura de tinta son 3.600 € más'."* **(D4)** | Mostrar la Quote con **grupo Producto** (retrofit base) y el **add-on** de temperatura de tinta como línea separada con su precio. Añadir una **alternativa de alcance** para comparar escenarios | Precio desglosado y add-ons de serie, en el mismo documento |
| **08** | Vendedor + Director de servicio | *"Vuestra calculadora de descuento (Ref. 41:40)… pero con el histórico que hoy no existe porque se aprueba por WhatsApp (Ref. 42:38)."* **(D3, D9)** | El banner de la cabecera avisa antes de prometer nada: descuento mezclado **11,15%**, pero la línea T100 lleva un **25%**, y eso son **dos firmas** (Manager y Director de Servicio). Pulsar **Enviar a aprobación** y ver el path del registro pasar a **Pending**. Ir a la pestaña **Approvals**, firmar el nivel de Manager con comentario, firmar el de Director, y ver el path quedar en **Approved** con las dos firmas en la traza | Deal guidance avisa *antes* de pedir aprobación: el vendedor sabe qué va a costar el descuento antes de prometerlo. El descuento mezclado tapaba un 25% en una línea, y el sistema lo caza solo. Cada firma queda auditada con fecha, persona y motivo |
| **09** | Vendedor de servicio | *"Mismo documento y misma calidad (Ref. 45:01), sin teclear el número de versión a mano y sin ficheros compartidos con 189 personas (Ref. 46:17)."* **(D5, D1)** | Pulsar **Create Proposal** en la oferta y elegir la plantilla **COMEXI_Propuesta_Retrofit** (o **Generate Quote Document**, mismo template, con el toggle *Send for e-signature* en **No**: la firma electrónica pide conexión DocuSign que la org de demo no tiene). Sale un PDF de 7 páginas con marca Comexi, listo para enviar: portada con la foto de la S2 DS, el caso **00001003** que originó todo con la petición del cliente literal, el veredicto de viabilidad del Advisor, las tres tablas de la oferta (producto, intervención, gastos) con el **15,00%** de la línea T100, el total de **15.322,18 EUR**, el reparto entre máquina, mano de obra y gastos, condiciones y anticipo, y la traza de que el descuento lo firmó alguien. Cliente pide un cambio → generar **versión 2**; número, histórico y comparativa automáticos | El documento no es una lista de productos: arrastra el expediente entero, del correo de entrada a la firma del descuento. Y lo que no arrastra es lo que no debe salir de casa: ni coste, ni margen, ni comisión del representante. Document Generation con versionado y permisos por perfil |
| **10** | Vendedor + Legal | *"Hoy generáis un segundo documento, el 'contrato de viabilidad', 99% igual a la oferta (Ref. 50:46). Aquí es el mismo hilo."* **(D7)** | Pulsar **Create Contract** en la oferta. Vuelve un contrato en **Draft** con los detalles ya escritos, ninguno tecleado: **Origen** (caso 174535, oportunidad, máquina `MSC000600`, modelo), **Alcance** (RET_OBS, T100, el PC con Windows 10 fuera de soporte), **Intervención** (Leeds, United Kingdom, 6 semanas, 26/10/2026, 36 horas, gastos a cargo de Comexi) y **Condiciones** (15.322,18 EUR, anticipo 30% = 4.596,65 EUR, Net 30, garantía 6 meses desde la aceptación). En la pestaña **Documents** ya está el contrato generado: las mismas 8 páginas de la propuesta más una página de **condiciones contractuales** con las seis cláusulas, y las seis aparecen en **Associated Clauses** | El contrato no se redacta: nace del hilo. El 99% duplicado a mano se copia solo, y el 1% que lo diferencia —el articulado— sale de la biblioteca de cláusulas, no del Word de nadie. Cada cláusula es trazable a una frase del Discovery |
| **11** | Operaciones + Finanzas | *"Elimina la doble entrada en SAP y la conversión manual de oferta a pedido (Ref. 52:00–53:27), y hace visible la dependencia del down payment que hoy vive en correos."* **(D6, D13)** | Llevar el contrato por su ciclo hasta **Signed** (el path del registro va Draft → In Approval Process → Negotiating → Awaiting Signature → Signed; el salto directo lo bloquea la propia plataforma). Al firmar, sin pulsar nada más, aparece el **Order** en **Activated** con las 10 líneas y **15.322,18 EUR**, y con los detalles ya escritos: **Origen** (caso 174535, oportunidad, `MSC000600`, modelo S2 DS), **Alcance** (RET_OBS, T100, el PC con Windows 10), **Intervención** (Leeds, United Kingdom, 6 semanas, 36 horas, gastos a cargo de Comexi) y **Anticipo y salida a SAP** (30% = 4.596,65 EUR, estado **Pendiente**, Net 30, código de cliente `SAP-UK-04412`). Abrir el **plan de fulfillment**: nueve pasos en tres grupos. Enviar códigos de material a SAP y planificar la intervención ya están **en curso**; el hito de anticipo se ha emitido solo; y **Arranque de ingeniería está en Pending**. Marcar **Confirmar cobro del anticipo** como completado y ver a ingeniería pasar a en curso en el mismo momento | Un pedido, tres destinos, sin reintroducir un solo dato: material a SAP con su código (`SAP-T100-UPDPC`, `SAP-W11-LIC`, `SAP-TEMP-TINTA`), intervención a operaciones y anticipo a finanzas. La regla que hoy vive en un correo —"ingeniería no arranca sin cobro"— es una dependencia nativa del plan que se ve bloquear y desbloquear en directo. Y el matiz que enseña que no es un semáforo tonto: operaciones **sí** puede reservar la ventana de intervención mientras finanzas espera el dinero; lo único que no arranca es ingeniería |
| **12** | Servicio | *"Cerrada la instalación, el Asset refleja la nueva configuración: el PC con Windows 11 ya forma parte de la base instalada."* **(D8, D9)** | El **Asset** `MSC000600` se actualiza (AssetAction/AssetActionSource). La próxima viabilidad se calcula sobre datos correctos | Cada venta mejora la calidad del dato para la siguiente |
| **13** | Dirección de servicio | *"Vuestra prioridad nº 3 y vuestro primer criterio de éxito (Ref. 1:00:27): visibilidad y transparencia."* **(D9)** | Abrir **dashboards**: tiempo medio de cotización, tasa de conversión, margen medio por familia, descuento medio, ofertas pendientes de aprobación, pipeline de retrofit por línea y país | El registro de ofertas y pedidos que construyen a mano, de serie |
| **14** | Agentforce | *"El preestudio masivo que pidió Ramón (Ref. 58:26): de reactivo a proactivo, que es el negocio que queréis hacer crecer."* **(D8, D12)** | El agente recorre la **base instalada**, detecta máquinas afectadas por obsolescencia de componente y propone la **campaña de retrofit** con oferta preconfigurada por máquina | Une viabilidad + oferta proactiva; aterriza que la agéntica necesita datos estructurados y Trust Layer |

**Cobertura:** las 14 escenas cubren los 13 dolores del Discovery (D1–D13) y las 3 prioridades declaradas por el cliente (viabilidad automatizada → escenas 2 y 14; precios desglosados → escena 7; dashboards → escena 13).

---

## 3. Especificación para Construcción en Cursor (Cursor Build Spec)

El detalle ejecutable —objetos, campos, CSVs de SFDMU, CML, Apex, metadata y cableado CumulusCI— está desglosado por dominio en [`build-spec/`](build-spec/00-README.md). Resumen:

### A. Modelo de Datos y Catálogo de Productos

- **Catálogo y productos** → [`build-spec/01-catalogo-atributos.md`](build-spec/01-catalogo-atributos.md)
  - `ProductCatalog` de servicio; `ProductCategory` jerárquico por familias observadas (**T0xx–T3xx** tall/slitting, **L2xx–L9xx** laminación, **C1xx** periféricos CTEC, **P0xx** piezas) y por etiquetas del cliente (`CTEC`, `RET_NEW_FEATURES`, `RET_OBS`, `RET_NEW_DESIGNS`, `RET_MAINT`).
  - Bundle configurable **T100 - UPDATE PC** con `ProductComponentGroup` + `ProductRelatedComponent`.
  - Add-on **control de temperatura de tinta** como `Product2` independiente (no componente).
  - Productos de **servicio** (horas de montaje/instalación/puesta en marcha) y de **gasto** (vuelo, taxi, hotel, dietas).
- **Modelos de precios** → [`build-spec/02-pricing-escandallo.md`](build-spec/02-pricing-escandallo.md)
  - `Pricebook2` + `PricebookEntry`; `CostBook` + `CostBookEntry` (hora técnico **56 €**, manutención **30 €**).
  - Objetivo de margen por producto (niveles observados 10% / 25% / 40%).

### B. Reglas de Negocio & Lógica de CPQ/Billing

- **Reglas de configuración (CML)** → [`build-spec/03-configurador-cml.md`](build-spec/03-configurador-cml.md): modelo `COMEXI_T100.cml` desplegado como `ExpressionSetDefinition` y asociado con `ExpressionSetConstraintObj`. Cualificación contra el Asset por modelo y antigüedad.
- **Lógica de precios (escandallo)** → [`build-spec/02-pricing-escandallo.md`](build-spec/02-pricing-escandallo.md): pricing procedure `COMEXI_RetrofitPricingProcedure` (registro de `ExpressionSet`) con la secuencia `ListPrice` → uplifts (`PriceAdjustmentMatrix`) → riesgo → comisión → márgenes por concepto (`AttributeDiscount`) → `MinimumPrice`.
- **Cadenas de aprobación** → [`build-spec/04-quote-margen-aprobaciones.md`](build-spec/04-quote-margen-aprobaciones.md): deal guidance por umbral de margen + proceso de aprobación con histórico.

### C. Datasets de Prueba (Seed Data)

Detalle en [`build-spec/08-seed-data.md`](build-spec/08-seed-data.md):

- **Cuentas y contactos:** Roberts Mart Co Ltd (Leeds, UK) con representante activo (para la comisión del 8%); contactos David Prieto (Service Manager) y Ramón Cabrales.
- **Base instalada:** Asset `MSC000600` (Comexi Proslit S2 DS) con la configuración instalada que incluye el PC obsoleto; una segunda máquina antigua para demostrar el veredicto *no viable sin ingeniería*.
- **Caso inicial:** Case `174535`, asunto "PC + Win", descripción "Actualitzem oferta W11 si us plau".
- **Cotización inicial:** creada vía `PlaceQuote` (nunca DML directo) para arrancar la demo con datos ya cargados.

> **Cableado del entorno** (flag `comexi`, planes SFDMU, flow `prepare_comexi_demo`): [`build-spec/09-cci-wiring.md`](build-spec/09-cci-wiring.md).

---

## 4. Matriz de Reemplazo Tecnológico

| Función Actual del Cliente | Herramienta Legacy | Funcionalidad Nativa Salesforce Revenue Cloud | Estado en Demo |
| :--- | :--- | :--- | :--- |
| Catálogo de 113 retrofits + fichas de producto | Google Sheets `SYS_Resume` + fichas en Drive | **Product Catalog Management** (`ProductCatalog`, `ProductCategory`, `ProductClassification`, `Product2`) | 100% Nativo (catálogo de demo con productos observados; extract completo pendiente — ver gaps) |
| Configurador: preguntas + opcionales | Pestañas `ETO_Options` / `ETO_Codes` | **Product Configurator + CML** (`ExpressionSetDefinition` + `ExpressionSetConstraintObj`) | 100% Nativo |
| Estudio de viabilidad sobre la máquina | Ingeniería + SAP + PLM + Excels en Drive | **Asset Lifecycle Management** + **ProductQualification** + **Agentforce** | 100% Nativo |
| Escandallo: coste, riesgos, garantía, RALF, márgenes | Pestaña `ALL_Escandall` | **Salesforce Pricing** (pricing procedure = `ExpressionSet`, `PriceAdjustmentMatrix`, `AttributeDiscount`, `MinimumPrice`) + `CostBook` | 100% Nativo |
| Precio base vs. coste vs. margen | Fórmulas de la hoja | `CostBook`/`CostBookEntry` (dato) + campos `COMEXI_Cost__c` / `COMEXI_Margin_Pct__c` (expuestos) | Nativo (config, no hay elemento "margen" en el motor: se calcula y se expone) |
| Precio desglosado y add-ons | "Lo que no está pensado" (Ref. 59:18) | **QuoteLineGroup** + add-on como `Product2` independiente | 100% Nativo |
| Calculadora de descuento | Pestaña `ALL_Escandall` | **Deal guidance** + campos de margen en tiempo real | 100% Nativo |
| Aprobación de descuento | Voz / Hangouts / **WhatsApp** / llamada | **Approval process** sobre Quote con umbral de margen + histórico | 100% Nativo |
| Generación de oferta multiidioma | Menú `COMEXI Launcher` → Google Docs (7 idiomas) | **Document Generation** (`DocumentTemplate`, `DocumentGenerationMechanism = ServerSide`) | 100% Nativo |
| Versionado de oferta | Número tecleado a mano + histórico de Google Docs | Versionado automático de **Quote** + generación de documento | 100% Nativo |
| Contrato de viabilidad + firma | Segundo Google Doc 99% igual a la oferta | **CLM** (`createContract`) + Document Generation | Nativo (contrato); **firma electrónica = gap, ver §5** |
| Doble entrada de oferta en SAP | Reintroducción manual en SAP | **DRO** `ProductFulfillmentDecompRule` + `IntegrationProviderDef` hacia SAP | Nativo (integración SAP simulada con mock en la demo) |
| Conversión oferta → pedido | Persona entra en SAP y transforma | Invocable **`createOrderFromQuote`** | 100% Nativo |
| Notificación de pedido + log | Menú `Entrada Comanda` + fila en base de datos | **Order** + platform events + reports | 100% Nativo |
| Seguimiento de down payment | Correo a Finanzas | **Billing** (`BillingMilestonePlan`) + gating de ingeniería | Nativo |
| Recomendación de producto | Función `=GEMINI()` en celda | **Agentforce** (NGA) sobre datos estructurados con Trust Layer | 100% Nativo (agnóstico de LLM: pueden mantener Gemini como modelo) |
| Dashboards y KPIs | Registro de ofertas/pedidos hecho a mano | **Reports & Dashboards** nativos | 100% Nativo |
| Gestión de cambios post-pedido | "Enviar correos e improvisad" (Ref. 56:59) | **Change orders** sobre el pedido con recálculo | Nativo (fuera del flujo principal de la demo) |

---

## 5. Restricciones, Gaps y Correcciones técnicas

Estos puntos condicionan la construcción y deben mantenerse visibles ante el cliente (detalle en [`build-spec/09-cci-wiring.md`](build-spec/09-cci-wiring.md)):

**Correcciones de modelo (validadas contra las skills de Revenue Cloud v66.0):**

1. **No existe un objeto `PricingProcedure`.** El pricing procedure es un registro de `ExpressionSet`; se despliega como `ExpressionSetDefinition` + `ExpressionSetDefinitionVersion`.
2. **El motor de pricing no tiene elemento de "coste" ni de "margen".** El coste vive en `CostBook`; el margen se calcula y se **expone en campos** de `Quote`/`QuoteLineItem`, que son los que disparan deal guidance y aprobación.
3. **CML no usa `implies` / `requires` / `excludes`.** Usa el operador `->` y las reglas `require()` / `exclude()` / `message()`.
4. **Nunca crear `Quote`/`QuoteLineItem` por DML directo** (deja el banner naranja de "precios no actualizados"): usar `PlaceQuote.PlaceQuoteRLMApexProcessor` o `POST /commerce/quotes/actions/place`.
5. **Firma electrónica nativa: no confirmada** en las skills RLM. Se marca como gap con decisión pendiente en [`build-spec/05-documento-contrato-firma.md`](build-spec/05-documento-contrato-firma.md).

**Gaps del Discovery (preguntas abiertas que condicionan escenas concretas):**

| Gap | Escena afectada |
| :--- | :--- |
| Roles y aprobaciones tras la reorganización del 1 de septiembre de 2026 | 3, 8 |
| Volumen anual de ofertas de retrofit y tasa de conversión | 13 (calibrar KPIs) |
| Nº medio de versiones por oferta y % renegociado | 9 |
| Integración SAP actual (middleware, quién la mantiene) | 11 |
| Multidivisa: ¿facturan en divisa local? | 6 (price book) |
| Packs de servicio gold/silver (hoy sin catalogar) | catálogo, extensión |
| Guardrails de seguridad de IA | 2, 14 |
| Licencias Salesforce actuales y aprendizaje del fallo de artículos de conocimiento | 2, 14 (discurso "pasito a pasito") |
| Catálogo completo (113 productos): requiere extract del Sheets del cliente | 4, 7 |

**Entorno:** existe la org conectada **`comexi`** (`sf`, API v67.0, Connected) y **ya tiene Revenue Cloud/RLM desplegado y poblado** (314 `Product2`, 15 `ExpressionSet`, 20 `DocumentTemplate`, 211 `ExpressionSetConstraintObj`, 3 `ProductCatalog` — probablemente el shape `qb` de `rlm-base-dev`). Hay **0 Assets**, así que la base instalada de Comexi hay que sembrarla. La fase de build parte de esta base RLM viva, no de cero (ver [`build-spec/09-cci-wiring.md`](build-spec/09-cci-wiring.md) §Estado de la org).
