#!/usr/bin/env python3
"""Construye las plantillas Doc Gen de retrofit de Comexi: oferta y contrato.

Genera un .docx maquetado con la marca Comexi que se despliega como plantilla
DocumentTemplate en:
    unpackaged/post_comexi/documentTemplates/COMEXI_Propuesta_Retrofit_1.dt  (--variant proposal)
    unpackaged/post_comexi/documentTemplates/COMEXI_Contrato_Retrofit_1.dt   (--variant contract)

Los dos variants salen del mismo codigo a proposito. El Discovery describe el
"contrato de viabilidad" como un documento "99% identico a la oferta" que el
vendedor duplica a mano, y ese duplicado es justo el dolor que la demo elimina:
si fueran dos scripts acabarian divergiendo igual que divergen hoy los dos
Google Docs. El variant contract cambia la portada, anade la pagina de
condiciones contractuales con las seis clausulas de la biblioteca CLM y ajusta
el bloque de firma. Todo lo demas es literalmente el mismo documento.

Las seis clausulas de CLAUSES tienen que decir lo mismo que las DocumentClause
que crea scripts/comexi/provision_clm_clauses.py. Ese script las registra en la
biblioteca (es lo que alimenta "Associated Clauses"); aqui se imprimen en el
papel. Si se toca una, hay que tocar la otra.

El documento NO lleva tokens: es una foto fija de la oferta 00000049 de Roberts
Mart Co Ltd. La escena de demo consiste en pulsar Create Proposal en esa oferta y
abrir el PDF, y lo que se lee en el PDF tiene que cuadrar al centimo con lo que se
ve en pantalla. Con tokens reales bastaria, pero el encargo era simular la
generacion, asi que el contenido va literal. La contrapartida esta asumida: si el
advisor regenera la oferta y cambia el numero o los importes, este documento sigue
contando lo de 00000049 y hay que volver a ejecutar este script con los datos
nuevos.

Las cifras del bloque DATOS proceden de la org (org comexi, 14/09/2026). Las
consultas que las devuelven estan anotadas encima de cada bloque para poder
refrescarlas sin adivinar.

El documento es integramente para el cliente: no lleva coste, ni margen, ni umbral
de margen. Lo unico que se cuenta del circuito interno es que el descuento paso por
una firma, que es argumento de venta; con cuanto margen queda Comexi, no.

Imagenes, todas ya versionadas en el repo:
    scripts/assets/comexi/Comexi-logo-web.png
    unpackaged/post_comexi/staticresources/COMEXI_MachineryImages/MAQ-S2-DS.jpg
    unpackaged/post_comexi/staticresources/COMEXI_ProductImages/T100*.png

Uso:
    python3 scripts/build_comexi_retrofit_proposal.py [--variant proposal|contract] [--output RUTA]
    python3 scripts/build_comexi_retrofit_proposal.py --variant all
"""

from __future__ import annotations

import argparse
from io import BytesIO
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor
from PIL import Image, ImageChops

REPO_ROOT = Path(__file__).resolve().parent.parent

TEMPLATES = REPO_ROOT / "unpackaged/post_comexi/documentTemplates"
DEFAULT_OUTPUTS = {
    "proposal": TEMPLATES / "COMEXI_Propuesta_Retrofit_1.dt",
    "contract": TEMPLATES / "COMEXI_Contrato_Retrofit_1.dt",
}

LOGO = REPO_ROOT / "scripts/assets/comexi/Comexi-logo-web.png"
MACHINERY = REPO_ROOT / "unpackaged/post_comexi/staticresources/COMEXI_MachineryImages"
PRODUCTS = REPO_ROOT / "unpackaged/post_comexi/staticresources/COMEXI_ProductImages"

# Marca Comexi, muestreada del logo oficial.
RED = "ED1848"
SLATE = "455560"
RED_SOFT = "FDECF0"
GREY_SOFT = "F4F5F6"
GREY_LINE = "D8DCE0"
WHITE = "FFFFFF"

BODY_FONT = "Arial"

# Ancho util con margenes de 2 cm en A4: 21,0 - 4,0 = 17,0 cm.
CONTENT_CM = 17.0


# ---------------------------------------------------------------------------
# DATOS: foto fija de la oferta 00000049 tal como esta en la org comexi.
# ---------------------------------------------------------------------------

# SELECT QuoteNumber, CreatedDate, Subtotal, GrandTotal, RLM_Discount_Percent__c,
#        COMEXI_Offer_Version__c, RLM_Payment_Terms__c
# FROM Quote WHERE Id = '0Q0bm000003QkdNCAS'
QUOTE = {
    "number": "00000049",
    "name": "Oferta Retrofit T100 - 174535",
    "version": "1",
    "date": "14/09/2026",
    "valid_until": "14/10/2026",
    "currency": "EUR",
    "subtotal": 16420.39,
    "discount_pct": 6.69,
    "discount_amount": 1098.21,
    "grand_total": 15322.18,
    "payment_terms": "Net 30",
}

# SELECT Name, BillingStreet, BillingCity, BillingState, BillingPostalCode,
#        BillingCountry, Phone, Website FROM Account WHERE Id = '001bm00002c3fqwAAA'
ACCOUNT = {
    "name": "Roberts Mart Co Ltd",
    "street": "Unit 7, Cross Green Industrial Estate",
    "street2": "Pontefract Road",
    "city": "Leeds",
    "state": "West Yorkshire",
    "postal_code": "LS9 0SF",
    "country": "United Kingdom",
    "phone": "+44 113 249 8800",
    "website": "www.robertsmart.co.uk",
}

# SELECT CaseNumber, Origin, Priority, Status, CreatedDate, Description,
#        Contact.Name, Contact.Email, Contact.Phone FROM Case WHERE CaseNumber = '00001003'
CASE = {
    "number": "00001003",
    "customer_ref": "174535",
    "subject": "174535 - PC + Win (Asset MSC000600)",
    "origin": "Email",
    "priority": "Alta",
    "status": "Nuevo",
    "created": "14/08/2026",
    "description": (
        "Actualitzem oferta W11 si us plau. Maquina: MSC000600 (Proslit S2 DS)."
    ),
    "contact_name": "David Prieto",
    "contact_email": "david.prieto@robertsmart.co.uk",
    "contact_phone": "+44 113 249 8812",
}

# SELECT Name, SerialNumber, Product2.Name, InstallDate, Status FROM Asset
# WHERE Name = 'MSC000600'
ASSET = {
    "name": "MSC000600",
    "serial": "MSC000600",
    "product": "Comexi S2 DS",
    "model": "S2 DS (antic Proslit S2 DS)",
    "install_date": "01/06/2015",
    "age_years": "11",
    "status": "Instalada",
    "obsolete": "MSC000600-PC · PC industrial amb Windows 10 (fi de suport)",
}

# SELECT Name, RecordType.Name, StageName, CloseDate, COMEXI_Viability_Status__c,
#        COMEXI_Advisor_Confidence__c, COMEXI_Needs_Engineering__c,
#        COMEXI_Viability_Rationale__c, Owner.Name
# FROM Opportunity WHERE Id = '006bm00000X6r6gAAB'
OPPORTUNITY = {
    "name": "Roberts Mart Co Ltd - Retrofit T100 (Case 174535)",
    "record_type": "Retrofitting",
    "stage": "Proposal/Quote",
    "close_date": "13/11/2026",
    "owner": "Manuel Galnares Milano",
    "viability": "Viable sin ingeniería",
    "confidence": "92%",
    "needs_engineering": "No",
    "validated_by": "COMEXI Retrofit Advisor (Agentforce)",
    "analysis_date": "14/09/2026",
}

# Literal de Opportunity.COMEXI_Viability_Rationale__c, sin reescribir.
RATIONALE_HEAD = "Veredicto del COMEXI Retrofit Advisor: VIABLE SIN INGENIERÍA."
RATIONALE_BULLETS = [
    (
        "Problema",
        "MSC000600-PC · PC industrial amb Windows 10 (fi de suport) de S2 DS "
        "(antic Proslit S2 DS) (antigüedad 11 años) corre un sistema operativo "
        "fuera de soporte. Es un riesgo de continuidad y de auditoría, no un "
        "fallo mecánico.",
    ),
    (
        "Solución",
        "retrofit T100 - UPDATE PC. Migra el PC de la línea a Windows 11 "
        "reutilizando la máquina; no requiere rediseño ni ingeniería a medida.",
    ),
    (
        "Encaje",
        "entra en el 80% de retrofits que no necesitan ingeniería. Se puede "
        "cotizar directamente sin escalar al comité técnico.",
    ),
    ("Confianza del análisis", "92%."),
]

# SELECT Product2.StockKeepingUnit, Product2.Name, Quantity, ListPrice, Discount,
#        NetTotalPrice, QuoteLineGroup.Name FROM QuoteLineItem
# WHERE QuoteId = '0Q0bm000003QkdNCAS' ORDER BY QuoteLineGroup.Name, LineNumber
#
# Cada grupo es (titulo, subtitulo, filas, subtotal). Una fila es
# (sku, concepto, cantidad, precio unitario, descuento, importe neto, sangrada).
GROUPS = [
    (
        "Producto",
        "Kit de retrofit y opciones sobre la máquina existente",
        [
            ("T100", "T100 - UPDATE PC", "1 ud", 7321.39, "15,00%", 6223.18, False),
            # Linea a cero: va sangrada bajo el kit y el "incluido" lo pone la columna
            # de importe, no la de descuento. No es un descuento, es alcance del kit.
            ("T100-W11", "Canvi de Windows 10 a Windows 11", "1 ud", 0.0, "—", 0.0, True),
            (
                "T100-TEMP",
                "Control de temperatura de tinta",
                "1 ud",
                3600.00,
                "—",
                3600.00,
                False,
            ),
        ],
        9823.18,
    ),
    (
        "Intervención",
        "36 horas de técnico en planta a 95,00 EUR/hora",
        [
            ("SRV-MEC", "Muntatge mecanic (CC/MM)", "16 h", 95.00, "—", 1520.00, False),
            (
                "SRV-ELE",
                "Instal.lacio electrica (IE)",
                "12 h",
                95.00,
                "—",
                1140.00,
                False,
            ),
            (
                "SRV-PME",
                "Posada en marxa software (PME)",
                "8 h",
                95.00,
                "—",
                760.00,
                False,
            ),
        ],
        3420.00,
    ),
    (
        "Gastos",
        "Desplazamiento y estancia del equipo en Leeds, a cargo de Comexi",
        [
            ("EXP-FLIGHT", "Bitllet d avio", "1 ud", 990.00, "—", 990.00, False),
            ("EXP-HOTEL", "Hotel", "1 ud", 660.00, "—", 660.00, False),
            ("EXP-MEAL", "Dietes", "3 ud", 99.00, "—", 297.00, False),
            ("EXP-TAXI", "Taxi", "1 ud", 132.00, "—", 132.00, False),
        ],
        2079.00,
    ),
]

# Fichas de producto de COMEXI_ProductImages, para la pagina de alcance.
SCOPE_IMAGES = [
    ("T100.png", "T100 - UPDATE PC"),
    ("T100-W11.png", "Windows 10 a Windows 11"),
    ("T100-TEMP.png", "Control de temperatura de tinta"),
]

# Reparto del importe entre los tres grupos de la oferta. Son los mismos subtotales
# de la pagina anterior con su peso sobre el total: responde a la primera pregunta que
# hace cualquiera al ver la cifra, cuanto de esto es maquina y cuanto es mano de obra.
COMPOSITION = [
    ("Producto: kit T100 y opciones", "9.823,18 EUR · 64,1%"),
    ("Intervención: 36 h de técnico en planta", "3.420,00 EUR · 22,3%"),
    ("Gastos de desplazamiento y estancia", "2.079,00 EUR · 13,6%"),
    ("Total de la propuesta", "15.322,18 EUR · 100%"),
]

# SELECT COMEXI_Intervention_Site__c, COMEXI_Intervention_Country__c,
#        COMEXI_Intervention_Weeks__c, COMEXI_Target_Intervention_Date__c,
#        COMEXI_Intervention_Hours__c, COMEXI_Expenses_Owner__c FROM Quote ...
PLANNING = [
    ("Emplazamiento de la intervención", "Leeds, United Kingdom"),
    ("Ventana de planificación", "6 semanas desde la aceptación"),
    ("Fecha objetivo de intervención", "26/10/2026"),
    ("Horas de técnico previstas", "36 h (16 CC/MM + 12 IE + 8 PME)"),
    ("Gastos de desplazamiento", "A cargo de Comexi"),
    ("Parada de línea estimada", "Dentro de la ventana de 36 h de intervención"),
]

# SELECT RLM_Payment_Terms__c, COMEXI_Down_Payment_Pct__c,
#        COMEXI_Down_Payment_Amount__c, COMEXI_Offer_Version__c FROM Quote ...
#
# Aqui no entran los componentes del escandallo (recargo de garantia, RALF, riesgo
# pais) ni la comision del representante. Son piezas de la procedura de precios que
# explican como se llega al importe, no condiciones que el cliente acepte, y la
# comision ademas le pone cifra a lo que Comexi paga por vender la oferta. Se ven en
# la pantalla de la oferta, que es donde tienen sentido, no en el PDF que se envia.
COMMERCIAL = [
    ("Condiciones de pago", "Net 30 (30 días fecha factura)"),
    ("Anticipo a la firma", "30% · 4.596,65 EUR"),
    ("Resto del importe", "A la puesta en marcha, con condiciones Net 30"),
    ("Divisa de la oferta", "EUR"),
]

# SELECT RLM_Discount_Percent__c, COMEXI_Max_Line_Discount_Pct__c,
#        RLM_Approval_Level__c, RLM_Approval_Status__c FROM Quote ...
#
# Sin margen ni umbral de margen: este documento se envia al cliente. Que el
# descuento paso por un circuito de firmas es un argumento de venta; con cuanto
# margen queda Comexi no es asunto suyo.
APPROVAL = [
    ("Descuento mezclado de la oferta", "6,69%"),
    ("Descuento máximo concedido en una línea", "15,00% (línea T100 - UPDATE PC)"),
    ("Niveles de firma exigidos", "1 · Manager"),
    ("Estado del circuito de aprobación", "Aprobado"),
    ("Firmado por", "Manuel Galnares Milano · 14/09/2026"),
]

NEXT_STEPS = [
    (
        "Aceptación de la oferta",
        "Firma de esta propuesta. La oferta 00000049 queda cerrada en el expediente "
        "con el descuento ya aprobado.",
    ),
    (
        "Anticipo",
        "Emisión de la factura del anticipo del 30% (4.596,65 EUR). El resto se "
        "factura a la puesta en marcha con condiciones Net 30.",
    ),
    (
        "Planificación",
        "Confirmación de la fecha de intervención dentro de la ventana de 6 semanas. "
        "Fecha objetivo actual: 26/10/2026.",
    ),
    (
        "Intervención en planta",
        "36 horas de técnico en Leeds: montaje mecánico, instalación eléctrica y "
        "puesta en marcha del software con validación de producción.",
    ),
]

VALIDITY = [
    "Oferta válida 30 días naturales desde la fecha de emisión: hasta el "
    "14/10/2026.",
    "Precios en EUR, impuestos no incluidos. Condiciones de pago Net 30 con un "
    "anticipo del 30% a la firma.",
    "El retrofit reutiliza la máquina instalada MSC000600. No requiere rediseño "
    "ni ingeniería a medida.",
    "La planificación de las 36 horas de intervención se confirma con el cliente "
    "una vez aceptada la oferta.",
    "El descuento recogido en esta propuesta está aprobado internamente y queda "
    "trazado en el expediente de la oferta 00000049.",
]

# El variant contract sustituye la lista anterior: un contrato firmado no tiene
# fecha de caducidad ni invita a aceptar nada, describe lo que ya se acordo. Y se
# queda sin "Siguientes pasos": el anticipo, la planificacion y la intervencion ya
# los fijan las clausulas 2, 5 y 4, repetirlos sobraba y ademas empujaba el bloque
# de firma a una novena pagina practicamente en blanco.
CONTRACT_VALIDITY = [
    "Este contrato recoge el alcance, los importes y las condiciones de la oferta "
    "00000049, aceptada por el cliente el 14/09/2026.",
    "Precios en EUR, impuestos no incluidos. Condiciones de pago Net 30 con un "
    "anticipo del 30% a la firma.",
    "El retrofit reutiliza la máquina instalada MSC000600. No requiere rediseño "
    "ni ingeniería a medida.",
    "Las 36 horas de intervención se ejecutan dentro de la ventana de 6 semanas "
    "acordada, con fecha objetivo 26/10/2026.",
    "El descuento aplicado está aprobado internamente y queda trazado en el "
    "expediente de la oferta 00000049.",
]

# Solo para --variant contract. Es el mismo texto que scripts/comexi/
# provision_clm_clauses.py registra como DocumentClause en la biblioteca CLM:
# alli viven como registros reutilizables y salen en Associated Clauses, aqui se
# imprimen en el papel que firma el cliente. Tocar una obliga a tocar la otra.
#
# Las seis salen del Discovery de COMEXI (Reverse Demo, 4 ago 2026). No hay
# propiedad intelectual, ni fuerza mayor, ni jurisdiccion: el cliente no las
# menciono y no se inventan clausulas legales para una demo.
CLAUSES = [
    (
        "Precio y exclusiones",
        [
            "El precio del presente contrato asciende a 15.322,18 EUR, impuestos no "
            "incluidos, y comprende exclusivamente el alcance descrito en el apartado "
            "de alcance de la solución.",
            "Quedan expresamente excluidos y a cargo del comprador la obra civil y las "
            "adaptaciones de la instalación existente, los suministros eléctricos y "
            "neumáticos hasta el punto de conexión, la retirada y gestión de los "
            "elementos sustituidos y los medios de elevación en planta.",
            "Cualquier ampliación del alcance solicitada por el comprador con "
            "posterioridad a la firma será objeto de oferta independiente.",
        ],
    ),
    (
        "Condiciones de pago",
        [
            "El comprador abonará un anticipo del 30% del precio del contrato, "
            "equivalente a 4.596,65 EUR, a la firma del presente documento.",
            "El saldo restante, 10.725,53 EUR, se abonará a 30 días fecha factura una "
            "vez emitida el acta de aceptación de la intervención.",
            "La recepción del anticipo es condición para el arranque de los trabajos "
            "de ingeniería y para la reserva de materiales. Comexi no iniciará el "
            "diseño definitivo ni la compra de componentes hasta la confirmación del "
            "cobro.",
        ],
    ),
    (
        "Garantía",
        [
            "Comexi garantiza los componentes suministrados y los trabajos ejecutados "
            "durante un periodo de seis meses.",
            "El cómputo de la garantía se inicia en la fecha de aceptación de la "
            "intervención, no en la fecha de entrega del material ni en la de firma "
            "del presente contrato.",
            "La garantía cubre la sustitución de los componentes defectuosos y la mano "
            "de obra necesaria para su reemplazo. No cubre los daños derivados de un "
            "uso distinto del previsto, de modificaciones realizadas por terceros sin "
            "autorización de Comexi o de la falta de mantenimiento preventivo.",
        ],
    ),
    (
        "Instalación y puesta en marcha",
        [
            "La intervención se ejecutará en la planta del comprador en Leeds (United "
            "Kingdom) sobre la máquina MSC000600 y comprende 36 horas de trabajo: 16 "
            "de montaje mecánico, 12 de instalación eléctrica y 8 de puesta en marcha "
            "de software, con las pruebas de aplicación correspondientes.",
            "Los gastos de desplazamiento y estancia del personal técnico de Comexi "
            "van a cargo de Comexi.",
            "El comprador pondrá la máquina a disposición de Comexi, libre de "
            "producción, durante toda la ventana de intervención acordada, y "
            "facilitará el acceso a la instalación y los medios de elevación "
            "necesarios.",
        ],
    ),
    (
        "Plazo de entrega",
        [
            "La ventana de intervención comprometida es de seis semanas desde la "
            "confirmación del anticipo, con fecha objetivo de intervención el 26 de "
            "octubre de 2026.",
            "El plazo queda condicionado a la recepción del anticipo y a la "
            "disponibilidad de la máquina en la fecha acordada.",
            "Cualquier reprogramación solicitada por el comprador con menos de quince "
            "días de antelación podrá desplazar la fecha de intervención en función de "
            "la ocupación del calendario de operaciones de Comexi.",
        ],
    ),
    (
        "Confidencialidad",
        [
            "Las partes se obligan a mantener la confidencialidad de toda la "
            "información técnica, comercial y de proceso a la que accedan con ocasión "
            "del presente contrato.",
            "La obligación alcanza a los planos, esquemas eléctricos, parámetros de "
            "proceso y configuraciones de software intercambiados durante la "
            "intervención, y subsiste durante los dos años siguientes a la "
            "finalización de los trabajos.",
            "Ninguna de las partes podrá difundir el contenido económico del presente "
            "contrato sin autorización escrita de la otra.",
        ],
    ),
]

# ---------------------------------------------------------------------------
# Utilidades OOXML
# ---------------------------------------------------------------------------

# Orden que impone el esquema a los hijos de w:tcPr. Insertar fuera de orden
# produce un docx que Word abre pero que el convertidor a PDF de Salesforce
# rechaza, asi que cada elemento se coloca en su hueco.
_TCPR_ORDER = [
    "cnfStyle",
    "tcW",
    "gridSpan",
    "hMerge",
    "vMerge",
    "tcBorders",
    "shd",
    "noWrap",
    "tcMar",
    "textDirection",
    "tcFitText",
    "vAlign",
    "hideMark",
]


# Lo mismo para w:trPr.
_TRPR_ORDER = [
    "cnfStyle",
    "divId",
    "gridBefore",
    "gridAfter",
    "wBefore",
    "wAfter",
    "cantSplit",
    "trHeight",
    "tblHeader",
    "tblCellSpacing",
    "jc",
    "hidden",
]

# Lo mismo para w:tblPr.
_TBLPR_ORDER = [
    "tblStyle",
    "tblpPr",
    "tblOverlap",
    "bidiVisual",
    "tblStyleRowBandSize",
    "tblStyleColBandSize",
    "tblW",
    "jc",
    "tblCellSpacing",
    "tblInd",
    "tblBorders",
    "shd",
    "tblLayout",
    "tblCellMar",
    "tblLook",
    "tblCaption",
    "tblDescription",
]


def _ordered_insert(parent, element, order) -> None:
    """Inserta element entre los hijos de parent segun el orden del esquema.

    Los convertidores a PDF del lado servidor son mas estrictos que Word: un
    w:tblCellMar colocado antes de w:tblLayout abre bien en Word y rompe la
    conversion. Por eso nada se anade con append a pelo.
    """
    tag = element.tag.split("}")[-1]
    position = order.index(tag)
    for child in parent:
        child_tag = child.tag.split("}")[-1]
        if child_tag in order and order.index(child_tag) > position:
            child.addprevious(element)
            return
    parent.append(element)


def _tcpr_insert(tcpr, element) -> None:
    _ordered_insert(tcpr, element, _TCPR_ORDER)


def _tblpr_insert(table, element) -> None:
    _ordered_insert(table._tbl.tblPr, element, _TBLPR_ORDER)


def shade(cell, fill: str) -> None:
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    _tcpr_insert(cell._tc.get_or_add_tcPr(), shd)


def cell_borders(cell, **edges) -> None:
    """Aplica bordes a un lado concreto: cell_borders(c, bottom=('single', 8, RED))."""
    borders = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        spec = edges.get(edge)
        if not spec:
            continue
        style, size, color = spec
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), style)
        el.set(qn("w:sz"), str(size))
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), color)
        borders.append(el)
    _tcpr_insert(cell._tc.get_or_add_tcPr(), borders)


def table_no_borders(table) -> None:
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "none")
        el.set(qn("w:sz"), "0")
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), "auto")
        borders.append(el)
    _tblpr_insert(table, borders)


def table_cell_margins(table, top=40, bottom=40, left=100, right=100) -> None:
    """Margenes internos de celda en veinteavos de punto, a nivel de tabla."""
    margins = OxmlElement("w:tblCellMar")
    for edge, value in (
        ("top", top),
        ("left", left),
        ("bottom", bottom),
        ("right", right),
    ):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:w"), str(value))
        el.set(qn("w:type"), "dxa")
        margins.append(el)
    _tblpr_insert(table, margins)


def set_widths(table, widths_cm) -> None:
    """Fija anchos por columna. Word solo los respeta si autofit esta apagado."""
    table.autofit = False
    layout = OxmlElement("w:tblLayout")
    layout.set(qn("w:type"), "fixed")
    _tblpr_insert(table, layout)
    for row in table.rows:
        for cell, width in zip(row.cells, widths_cm):
            cell.width = Cm(width)


def row_height(row, cm: float) -> None:
    height = OxmlElement("w:trHeight")
    height.set(qn("w:val"), str(int(cm * 567)))
    height.set(qn("w:hRule"), "atLeast")
    _ordered_insert(row._tr.get_or_add_trPr(), height, _TRPR_ORDER)


def no_split(row) -> None:
    trpr = row._tr.get_or_add_trPr()
    _ordered_insert(trpr, OxmlElement("w:cantSplit"), _TRPR_ORDER)


def repeat_header(row) -> None:
    trpr = row._tr.get_or_add_trPr()
    _ordered_insert(trpr, OxmlElement("w:tblHeader"), _TRPR_ORDER)


def keep_together(table) -> None:
    """Evita que la tabla se corte entre paginas.

    Word no tiene un "no partir tabla": se consigue marcando keepNext en todas las
    filas menos la ultima. Sin esto un grupo de la oferta se parte por la mitad y el
    subtotal aparece solo al principio de la pagina siguiente.
    """
    for row in table.rows:
        no_split(row)
    for row in table.rows[:-1]:
        for cell in row.cells:
            for paragraph in cell.paragraphs:
                paragraph.paragraph_format.keep_with_next = True


def field(paragraph, instruction: str, cached: str) -> None:
    """Inserta un campo de Word con resultado en cache (PAGE, NUMPAGES)."""
    run = paragraph.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = instruction
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    text = OxmlElement("w:t")
    text.text = cached
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    for element in (begin, instr, separate, text, end):
        run._r.append(element)
    return run


# ---------------------------------------------------------------------------
# Utilidades de contenido
# ---------------------------------------------------------------------------


def strip_cell(cell) -> None:
    """Vacia la celda de parrafos. Quien llama tiene que anadir los suyos.

    Hace falta despues de merge: python-docx concatena los parrafos de todas las
    celdas fusionadas, asi que una fila de subtotal quedaria con cinco lineas de
    alto por los cuatro parrafos vacios que arrastra.
    """
    for paragraph in list(cell.paragraphs):
        paragraph._p.getparent().remove(paragraph._p)


def clear_cell(cell):
    """Deja la celda con un unico parrafo vacio y lo devuelve."""
    strip_cell(cell)
    return cell.add_paragraph()


def eur(value: float) -> str:
    """Formato espanol: 15.322,18."""
    return f"{value:,.2f}".replace(",", "\u00a0").replace(".", ",").replace(
        "\u00a0", "."
    )


def flatten(path: Path, width_px: int | None = None) -> BytesIO:
    """Aplana la imagen sobre blanco y la devuelve como PNG en memoria.

    El logo es un PNG con paleta y canal alfa. Word lo abre, pero el convertidor
    a PDF del lado servidor pinta el alfa en negro, asi que se aplana antes de
    incrustarlo.
    """
    image = Image.open(path).convert("RGBA")
    canvas = Image.new("RGBA", image.size, (255, 255, 255, 255))
    canvas.alpha_composite(image)
    flat = canvas.convert("RGB")
    if width_px and flat.width > width_px:
        height = round(flat.height * width_px / flat.width)
        flat = flat.resize((width_px, height), Image.LANCZOS)
    buffer = BytesIO()
    flat.save(buffer, format="PNG")
    buffer.seek(0)
    return buffer


def trimmed(path: Path, pad_px: int = 8) -> BytesIO:
    """Recorta la imagen a su contenido y la devuelve como PNG en memoria.

    Las fotos de COMEXI_MachineryImages estan encajadas por contain en un lienzo
    640x480, asi que la de la S2 DS arrastra 98 px de blanco arriba y otros 98 abajo.
    Incrustada tal cual, en la portada eso son casi cuatro centimetros de hueco que
    parecen un fallo de maquetacion.
    """
    image = Image.open(path).convert("RGB")
    background = Image.new("RGB", image.size, (255, 255, 255))
    mask = ImageChops.difference(image, background).convert("L")
    box = mask.point(lambda value: 255 if value > 12 else 0).getbbox()
    if box:
        left, top, right, bottom = box
        image = image.crop(
            (
                max(0, left - pad_px),
                max(0, top - pad_px),
                min(image.width, right + pad_px),
                min(image.height, bottom + pad_px),
            )
        )
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    buffer.seek(0)
    return buffer


def style_run(
    run,
    size: float = 9.5,
    bold: bool = False,
    color: str = SLATE,
    caps: bool = False,
    italic: bool = False,
    spacing: int | None = None,
) -> None:
    run.font.name = BODY_FONT
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = RGBColor.from_string(color)
    if caps:
        run.font.all_caps = True
    if spacing:
        rpr = run._r.get_or_add_rPr()
        el = OxmlElement("w:spacing")
        el.set(qn("w:val"), str(spacing))
        rpr.append(el)


def write(
    cell,
    text: str,
    size: float = 9.5,
    bold: bool = False,
    color: str = SLATE,
    align=WD_ALIGN_PARAGRAPH.LEFT,
    caps: bool = False,
    space_after: int = 0,
    italic: bool = False,
) -> None:
    paragraph = cell.paragraphs[0]
    paragraph.alignment = align
    paragraph.paragraph_format.space_before = Pt(0)
    paragraph.paragraph_format.space_after = Pt(space_after)
    style_run(
        paragraph.add_run(text),
        size=size,
        bold=bold,
        color=color,
        caps=caps,
        italic=italic,
    )


def para(
    doc,
    text: str = "",
    size: float = 9.5,
    bold: bool = False,
    color: str = SLATE,
    align=WD_ALIGN_PARAGRAPH.LEFT,
    space_before: int = 0,
    space_after: int = 0,
    caps: bool = False,
    italic: bool = False,
    spacing: int | None = None,
):
    paragraph = doc.add_paragraph()
    paragraph.alignment = align
    paragraph.paragraph_format.space_before = Pt(space_before)
    paragraph.paragraph_format.space_after = Pt(space_after)
    if text:
        style_run(
            paragraph.add_run(text),
            size=size,
            bold=bold,
            color=color,
            caps=caps,
            italic=italic,
            spacing=spacing,
        )
    return paragraph


def page_break(doc) -> None:
    """Empieza pagina nueva sin dejar ninguna en blanco.

    El add_page_break de python-docx mete un salto explicito en un parrafo con el
    estilo Normal. Si a la pagina que se cierra no le queda ni esa media linea, el
    parrafo portador se va a la pagina siguiente y el salto la deja vacia: pasa exacto
    entre las condiciones y la pagina de firma, que llenan la suya al milimetro.

    Con pageBreakBefore el parrafo es el que arranca la pagina nueva, asi que no
    necesita hueco en la anterior y el efecto es el mismo. Se deja a 1 pt para que no
    empuje el titulo de seccion hacia abajo.
    """
    paragraph = doc.add_paragraph()
    paragraph.paragraph_format.page_break_before = True
    paragraph.paragraph_format.space_before = Pt(0)
    paragraph.paragraph_format.space_after = Pt(0)
    paragraph.paragraph_format.line_spacing = 1
    paragraph.add_run().font.size = Pt(1)


_section_counter = 0


def reset_sections() -> None:
    """Reinicia la numeracion. Lo llama build() antes de escribir la portada."""
    global _section_counter
    _section_counter = 0


def section_title(doc, text: str) -> None:
    """Titulo de seccion: numero en rojo, texto en pizarra y filete inferior.

    El numero se lleva solo. El variant contract intercala una seccion de
    clausulas en mitad del documento, y con los numeros escritos a mano habria
    que renumerar las dos ultimas paginas cada vez que se toca el orden.
    """
    global _section_counter
    _section_counter += 1
    number = f"{_section_counter:02d}"
    table = doc.add_table(rows=1, cols=1)
    table_no_borders(table)
    table_cell_margins(table, top=0, bottom=60, left=0, right=0)
    set_widths(table, [CONTENT_CM])
    cell = table.rows[0].cells[0]
    cell_borders(cell, bottom=("single", 12, RED))
    paragraph = cell.paragraphs[0]
    paragraph.paragraph_format.space_before = Pt(0)
    paragraph.paragraph_format.space_after = Pt(0)
    style_run(paragraph.add_run(f"{number}  "), size=12, bold=True, color=RED)
    style_run(paragraph.add_run(text.upper()), size=12, bold=True, color=SLATE, spacing=20)
    para(doc, space_after=4)


def kv_table(doc, rows, label_cm: float = 6.2) -> None:
    """Tabla de pares etiqueta/valor con la etiqueta sombreada."""
    table = doc.add_table(rows=len(rows), cols=2)
    table_no_borders(table)
    table_cell_margins(table)
    set_widths(table, [label_cm, CONTENT_CM - label_cm])
    for index, (label, value) in enumerate(rows):
        row = table.rows[index]
        row_height(row, 0.62)
        fill = GREY_SOFT if index % 2 == 0 else WHITE
        for cell in row.cells:
            shade(cell, fill)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            cell_borders(cell, bottom=("single", 4, GREY_LINE))
        write(row.cells[0], label, size=9, bold=True, color=SLATE)
        write(row.cells[1], value, size=9.5)
    keep_together(table)
    para(doc, space_after=6)


def quote_box(doc, heading: str, lines) -> None:
    """Bloque citado con barra roja a la izquierda, para texto literal."""
    table = doc.add_table(rows=1, cols=2)
    table_no_borders(table)
    table_cell_margins(table, top=100, bottom=100, left=0, right=0)
    set_widths(table, [0.12, CONTENT_CM - 0.12])
    bar, body = table.rows[0].cells
    shade(bar, RED)
    shade(body, RED_SOFT)
    strip_cell(body)
    if heading:
        paragraph = body.add_paragraph()
        paragraph.paragraph_format.left_indent = Cm(0.35)
        paragraph.paragraph_format.space_after = Pt(4)
        style_run(paragraph.add_run(heading), size=9.5, bold=True, color=RED)
    for index, (lead, text) in enumerate(lines):
        paragraph = body.add_paragraph()
        paragraph.paragraph_format.left_indent = Cm(0.35)
        paragraph.paragraph_format.space_after = Pt(0 if index == len(lines) - 1 else 3)
        if lead:
            style_run(paragraph.add_run(f"{lead}: "), size=9, bold=True, color=SLATE)
        style_run(paragraph.add_run(text), size=9, color=SLATE)
    para(doc, space_after=6)


def lines_table(doc, title: str, subtitle: str, rows, subtotal: float) -> None:
    """Tabla de lineas de oferta con cabecera roja y subtotal del grupo.

    Los rotulos van abreviados y la columna de importe sobredimensionada porque en
    A4 con seis columnas no cabe "Referencia" ni "9.823,18 EUR" sin partirse en dos
    lineas, y una tabla de precios con cabeceras troceadas no la firma nadie.
    """
    widths = [2.3, 6.2, 1.4, 2.4, 1.8, 2.9]

    caption = doc.add_paragraph()
    caption.paragraph_format.space_before = Pt(4)
    caption.paragraph_format.space_after = Pt(3)
    caption.paragraph_format.keep_with_next = True
    style_run(caption.add_run(title.upper()), size=10, bold=True, color=SLATE, spacing=16)
    style_run(caption.add_run(f"   {subtitle}"), size=8.5, color="7A848D", italic=True)

    table = doc.add_table(rows=len(rows) + 2, cols=6)
    table_no_borders(table)
    table_cell_margins(table, top=50, bottom=50)
    set_widths(table, widths)

    header = table.rows[0]
    row_height(header, 0.6)
    repeat_header(header)
    headings = [
        ("Ref.", WD_ALIGN_PARAGRAPH.LEFT),
        ("Concepto", WD_ALIGN_PARAGRAPH.LEFT),
        ("Cant.", WD_ALIGN_PARAGRAPH.CENTER),
        ("Precio unitario", WD_ALIGN_PARAGRAPH.RIGHT),
        ("Dto.", WD_ALIGN_PARAGRAPH.CENTER),
        ("Importe neto", WD_ALIGN_PARAGRAPH.RIGHT),
    ]
    for cell, (label, align) in zip(header.cells, headings):
        shade(cell, RED)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        write(cell, label, size=8, bold=True, color=WHITE, align=align, caps=True)

    for index, (sku, concept, qty, unit, discount, net, indented) in enumerate(rows):
        row = table.rows[index + 1]
        row_height(row, 0.6)
        fill = WHITE if index % 2 == 0 else GREY_SOFT
        for cell in row.cells:
            shade(cell, fill)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            cell_borders(cell, bottom=("single", 4, GREY_LINE))

        write(row.cells[0], sku, size=8, color="7A848D")
        label = f"↳ {concept}" if indented else concept
        write(row.cells[1], label, size=8.5 if indented else 9, bold=not indented)
        write(row.cells[2], qty, size=9, align=WD_ALIGN_PARAGRAPH.CENTER)
        write(
            row.cells[3],
            eur(unit) if unit else "—",
            size=9,
            align=WD_ALIGN_PARAGRAPH.RIGHT,
        )
        write(
            row.cells[4],
            discount,
            size=8.5,
            bold=discount.endswith("%"),
            color=RED if discount.endswith("%") else SLATE,
            align=WD_ALIGN_PARAGRAPH.CENTER,
        )
        write(
            row.cells[5],
            eur(net) if net else "incluido",
            size=9.5,
            bold=True,
            align=WD_ALIGN_PARAGRAPH.RIGHT,
        )

    footer = table.rows[-1]
    row_height(footer, 0.6)
    for cell in footer.cells:
        shade(cell, RED_SOFT)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    label_cell = footer.cells[0].merge(footer.cells[4])
    clear_cell(label_cell)
    write(
        label_cell,
        f"Subtotal {title.lower()}",
        size=9,
        bold=True,
        color=RED,
        align=WD_ALIGN_PARAGRAPH.RIGHT,
        caps=True,
    )
    write(
        footer.cells[-1],
        f"{eur(subtotal)} {QUOTE['currency']}",
        size=9.5,
        bold=True,
        color=RED,
        align=WD_ALIGN_PARAGRAPH.RIGHT,
    )
    keep_together(table)
    para(doc, space_after=8)


# ---------------------------------------------------------------------------
# Paginas
# ---------------------------------------------------------------------------


def build_header_footer(section, title: str | None = None, pages: str = "7") -> None:
    header = section.header
    header.is_linked_to_previous = False
    # add_table anade al final del contenedor, asi que el parrafo vacio que trae
    # el header de serie quedaria por encima del logo empujandolo hacia abajo.
    for paragraph in list(header.paragraphs):
        paragraph._p.getparent().remove(paragraph._p)
    table = header.add_table(rows=1, cols=2, width=Cm(CONTENT_CM))
    table_no_borders(table)
    table_cell_margins(table, top=0, bottom=80, left=0, right=0)
    set_widths(table, [6.0, CONTENT_CM - 6.0])
    left, right = table.rows[0].cells
    for cell in (left, right):
        cell_borders(cell, bottom=("single", 8, RED))
        cell.vertical_alignment = WD_ALIGN_VERTICAL.BOTTOM

    logo_paragraph = left.paragraphs[0]
    logo_paragraph.paragraph_format.space_before = Pt(0)
    logo_paragraph.paragraph_format.space_after = Pt(0)
    logo_paragraph.add_run().add_picture(flatten(LOGO, 900), width=Cm(4.2))

    write(
        right,
        title or f"Propuesta de retrofit · Oferta {QUOTE['number']} · {QUOTE['date']}",
        size=8,
        color="7A848D",
        align=WD_ALIGN_PARAGRAPH.RIGHT,
        caps=True,
    )
    # Un parrafo minimo tras el filete: sin el, el cuerpo arranca pegado a la linea.
    trailing = header.add_paragraph()
    trailing.paragraph_format.space_before = Pt(0)
    trailing.paragraph_format.space_after = Pt(0)
    style_run(trailing.add_run(""), size=2)

    footer = section.footer
    footer.is_linked_to_previous = False
    paragraph = footer.paragraphs[0]
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.space_before = Pt(0)
    style_run(
        paragraph.add_run(
            "Comexi Group Industries, S.A.U. · Ctra. Nacional II, km 705 · "
            "17457 Riudellots de la Selva (Girona), España · www.comexi.com"
        ),
        size=7.5,
        color="9AA3AA",
    )
    numbering = footer.add_paragraph()
    numbering.alignment = WD_ALIGN_PARAGRAPH.CENTER
    numbering.paragraph_format.space_before = Pt(2)
    style_run(numbering.add_run("Página "), size=7.5, color="9AA3AA")
    style_run(field(numbering, "PAGE", "1"), size=7.5, color="9AA3AA")
    style_run(numbering.add_run(" de "), size=7.5, color="9AA3AA")
    # El valor cacheado es lo que ve quien abra el docx sin recalcular campos; el
    # contrato lleva una pagina mas que la oferta por las clausulas.
    style_run(field(numbering, "NUMPAGES", pages), size=7.5, color="9AA3AA")


def page_cover(doc, variant: str = "proposal") -> None:
    contract = variant == "contract"
    para(doc, space_after=2)

    para(
        doc,
        "Contrato de viabilidad" if contract else "Propuesta comercial",
        size=10,
        bold=True,
        color=RED,
        caps=True,
        spacing=40,
        space_after=2,
    )
    para(doc, "RETROFIT DE MÁQUINA", size=30, bold=True, color=SLATE, space_after=0)
    para(
        doc,
        "Actualización del PC de línea y migración a Windows 11",
        size=13,
        color="7A848D",
        space_after=10,
    )

    picture = doc.add_paragraph()
    picture.alignment = WD_ALIGN_PARAGRAPH.CENTER
    picture.paragraph_format.space_after = Pt(2)
    # El interlineado 1,15 del estilo Normal se aplica tambien a la linea que contiene
    # la imagen, asi que un 15% de 9 cm de foto se convierte en un hueco de 1,4 cm.
    picture.paragraph_format.line_spacing = 1
    picture.add_run().add_picture(trimmed(MACHINERY / "MAQ-S2-DS.jpg"), width=Cm(13.5))
    para(
        doc,
        "Comexi S2 DS (antic Proslit S2 DS) · Activo MSC000600 · "
        "Instalada en 2015 en Leeds (United Kingdom)",
        size=8,
        color="9AA3AA",
        align=WD_ALIGN_PARAGRAPH.CENTER,
        italic=True,
        space_after=12,
    )

    rows = [
        ("Cliente", ACCOUNT["name"]),
        ("Máquina objeto del retrofit", f"{ASSET['name']} · {ASSET['product']}"),
        ("Solución propuesta", "T100 - UPDATE PC (retrofit por obsolescencia)"),
    ]
    if contract:
        rows += [
            (
                "Oferta contratada",
                f"{QUOTE['number']} · versión {QUOTE['version']} · "
                f"aceptada el {QUOTE['date']}",
            ),
            (
                "Origen de la solicitud",
                f"Caso {CASE['number']} · referencia de cliente {CASE['customer_ref']}",
            ),
            ("Condiciones", "Las recogidas en el apartado de condiciones contractuales"),
        ]
    else:
        rows += [
            (
                "Referencia de la oferta",
                f"{QUOTE['number']} · versión {QUOTE['version']} · "
                f"emitida el {QUOTE['date']}",
            ),
            (
                "Origen de la solicitud",
                f"Caso {CASE['number']} · referencia de cliente "
                f"{CASE['customer_ref']}",
            ),
            ("Validez de la oferta", f"Hasta el {QUOTE['valid_until']}"),
        ]
    kv_table(doc, rows, label_cm=6.6)

    total = doc.add_table(rows=1, cols=2)
    table_no_borders(total)
    table_cell_margins(total, top=140, bottom=140, left=200, right=200)
    set_widths(total, [10.0, CONTENT_CM - 10.0])
    row = total.rows[0]
    row_height(row, 1.35)
    for cell in row.cells:
        shade(cell, RED)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    write(
        row.cells[0],
        "Importe total del contrato" if contract else "Importe total de la propuesta",
        size=11,
        bold=True,
        color=WHITE,
        caps=True,
    )
    write(
        row.cells[1],
        f"{eur(QUOTE['grand_total'])} {QUOTE['currency']}",
        size=18,
        bold=True,
        color=WHITE,
        align=WD_ALIGN_PARAGRAPH.RIGHT,
    )


def page_context(doc) -> None:
    page_break(doc)

    section_title(doc, "Cliente y destinatario")
    table = doc.add_table(rows=1, cols=2)
    table_no_borders(table)
    table_cell_margins(table, top=120, bottom=120, left=160, right=160)
    set_widths(table, [8.5, 8.5])
    left, right = table.rows[0].cells
    for cell in (left, right):
        shade(cell, GREY_SOFT)
        strip_cell(cell)

    def block(cell, heading, lines):
        paragraph = cell.add_paragraph()
        paragraph.paragraph_format.space_after = Pt(4)
        style_run(paragraph.add_run(heading), size=8, bold=True, color=RED, caps=True, spacing=20)
        for index, (text, bold) in enumerate(lines):
            item = cell.add_paragraph()
            item.paragraph_format.space_after = Pt(0 if index == len(lines) - 1 else 1)
            style_run(item.add_run(text), size=9, bold=bold)

    block(
        left,
        "Dirección de facturación",
        [
            (ACCOUNT["name"], True),
            (ACCOUNT["street"], False),
            (ACCOUNT["street2"], False),
            (f"{ACCOUNT['postal_code']} {ACCOUNT['city']}", False),
            (f"{ACCOUNT['state']} · {ACCOUNT['country']}", False),
            (f"Tel. {ACCOUNT['phone']} · {ACCOUNT['website']}", False),
        ],
    )
    block(
        right,
        "Persona de contacto",
        [
            (CASE["contact_name"], True),
            (CASE["contact_email"], False),
            (f"Tel. {CASE['contact_phone']}", False),
            ("", False),
            (f"Responsable Comexi: {OPPORTUNITY['owner']}", False),
            (f"Emplazamiento de la máquina: {ACCOUNT['city']}, {ACCOUNT['country']}", False),
        ],
    )
    para(doc, space_after=8)

    section_title(doc, "Origen de la solicitud")
    kv_table(
        doc,
        [
            ("Caso de servicio", f"{CASE['number']} · {CASE['subject']}"),
            ("Referencia del cliente", CASE["customer_ref"]),
            ("Canal de entrada", CASE["origin"]),
            ("Prioridad", CASE["priority"]),
            ("Fecha de entrada", CASE["created"]),
            ("Solicitado por", f"{CASE['contact_name']} ({CASE['contact_email']})"),
        ],
    )
    quote_box(
        doc,
        "Petición recibida del cliente, literal",
        [("", f"«{CASE['description']}»")],
    )

    section_title(doc, "Máquina objeto del retrofit")
    kv_table(
        doc,
        [
            ("Activo", ASSET["name"]),
            ("Número de serie", ASSET["serial"]),
            ("Modelo", ASSET["model"]),
            ("Fecha de instalación", f"{ASSET['install_date']} ({ASSET['age_years']} años)"),
            ("Estado del activo", ASSET["status"]),
            ("Componente obsoleto identificado", ASSET["obsolete"]),
        ],
    )


def page_viability(doc) -> None:
    page_break(doc)

    section_title(doc, "Análisis de viabilidad")
    kv_table(
        doc,
        [
            ("Veredicto", OPPORTUNITY["viability"]),
            ("Confianza del análisis", OPPORTUNITY["confidence"]),
            ("Requiere ingeniería a medida", OPPORTUNITY["needs_engineering"]),
            ("Analizado por", OPPORTUNITY["validated_by"]),
            ("Fecha del análisis", OPPORTUNITY["analysis_date"]),
        ],
    )
    quote_box(doc, RATIONALE_HEAD, RATIONALE_BULLETS)

    section_title(doc, "Expediente comercial")
    kv_table(
        doc,
        [
            ("Oportunidad", OPPORTUNITY["name"]),
            ("Tipo de operación", OPPORTUNITY["record_type"]),
            ("Etapa", OPPORTUNITY["stage"]),
            ("Cierre previsto", OPPORTUNITY["close_date"]),
            ("Responsable comercial", OPPORTUNITY["owner"]),
            ("Oferta asociada", f"{QUOTE['number']} · {QUOTE['name']}"),
        ],
    )

    para(
        doc,
        "Trazabilidad de la operación: la petición del cliente entra como caso "
        f"{CASE['number']} por {CASE['origin'].lower()}, el análisis de "
        "viabilidad la clasifica como retrofit por obsolescencia sin ingeniería, "
        "y de ahí nace la oportunidad y esta oferta. Todo el recorrido queda "
        "registrado en el expediente, incluidas las firmas del descuento.",
        size=9,
        color="7A848D",
        italic=True,
        space_before=4,
    )


def page_scope(doc) -> None:
    page_break(doc)

    section_title(doc, "Alcance de la solución")
    table = doc.add_table(rows=2, cols=3)
    table_no_borders(table)
    table_cell_margins(table, top=0, bottom=0, left=60, right=60)
    set_widths(table, [CONTENT_CM / 3] * 3)
    for index, (filename, caption) in enumerate(SCOPE_IMAGES):
        picture_cell = table.rows[0].cells[index]
        paragraph = picture_cell.paragraphs[0]
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        paragraph.paragraph_format.space_after = Pt(2)
        paragraph.paragraph_format.line_spacing = 1
        paragraph.add_run().add_picture(str(PRODUCTS / filename), width=Cm(4.1))
        write(
            table.rows[1].cells[index],
            caption,
            size=8,
            bold=True,
            color=SLATE,
            align=WD_ALIGN_PARAGRAPH.CENTER,
        )
    para(doc, space_after=4)

    para(
        doc,
        "El retrofit T100 - UPDATE PC sustituye el PC industrial de la línea y "
        "migra el sistema de Windows 10 a Windows 11 reutilizando la máquina "
        "S2 DS instalada. Se incorpora además el control de temperatura de tinta "
        "solicitado. La intervención la ejecuta el equipo técnico de Comexi en "
        "planta del cliente, en Leeds.",
        size=9.5,
        space_after=8,
    )

    quote_box(
        doc,
        "Qué incluye la intervención",
        [
            ("Kit T100", "sustitución del PC industrial de la línea y migración del "
             "sistema de Windows 10 a Windows 11, con la configuración de la máquina "
             "trasladada al equipo nuevo."),
            ("Opción de temperatura de tinta", "instalación del control de "
             "temperatura de tinta sobre la máquina existente."),
            ("Puesta en marcha", "montaje mecánico, instalación eléctrica y puesta en "
             "marcha del software, con validación de producción antes de dejar la línea."),
            ("No incluye", "rediseño de la máquina ni ingeniería a medida: el retrofit "
             "reutiliza la S2 DS instalada en 2015."),
        ],
    )


def page_economics(doc) -> None:
    page_break(doc)

    section_title(doc, "Detalle económico")
    for title, subtitle, rows, subtotal in GROUPS:
        lines_table(doc, title, subtitle, rows, subtotal)

    summary = doc.add_table(rows=3, cols=2)
    summary.alignment = WD_TABLE_ALIGNMENT.RIGHT
    table_no_borders(summary)
    table_cell_margins(summary, top=70, bottom=70, left=160, right=160)
    set_widths(summary, [6.6, 4.4])
    rows = [
        ("Subtotal", f"{eur(QUOTE['subtotal'])} {QUOTE['currency']}", False),
        (
            f"Descuento aplicado ({eur(QUOTE['discount_pct'])}%)",
            f"-{eur(QUOTE['discount_amount'])} {QUOTE['currency']}",
            False,
        ),
        ("Total de la propuesta", f"{eur(QUOTE['grand_total'])} {QUOTE['currency']}", True),
    ]
    for index, (label, value, emphasis) in enumerate(rows):
        row = summary.rows[index]
        row_height(row, 0.7 if emphasis else 0.6)
        for cell in row.cells:
            shade(cell, RED if emphasis else GREY_SOFT)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
            if not emphasis:
                cell_borders(cell, bottom=("single", 4, GREY_LINE))
        write(
            row.cells[0],
            label,
            size=10 if emphasis else 9,
            bold=True,
            color=WHITE if emphasis else SLATE,
            caps=emphasis,
        )
        write(
            row.cells[1],
            value,
            size=12 if emphasis else 9.5,
            bold=True,
            color=WHITE if emphasis else SLATE,
            align=WD_ALIGN_PARAGRAPH.RIGHT,
        )
    para(doc, space_after=4)
    para(
        doc,
        "Importes en EUR, impuestos no incluidos. El descuento del "
        f"{eur(QUOTE['discount_pct'])}% es el efectivo sobre el conjunto de la "
        "oferta y procede del 15,00% concedido en la línea del kit T100.",
        size=8.5,
        color="9AA3AA",
        italic=True,
    )


def page_conditions(doc) -> None:
    page_break(doc)

    section_title(doc, "Composición del importe")
    kv_table(doc, COMPOSITION, label_cm=8.6)

    section_title(doc, "Planificación de la intervención")
    kv_table(doc, PLANNING, label_cm=8.2)

    section_title(doc, "Condiciones económicas")
    kv_table(doc, COMMERCIAL, label_cm=8.2)

    section_title(doc, "Trazabilidad de la aprobación")
    kv_table(doc, APPROVAL, label_cm=8.2)
    para(
        doc,
        "En Comexi ningún descuento se aprueba fuera del sistema: cada firma queda "
        "registrada con persona, fecha y motivo.",
        size=9,
        color="7A848D",
        italic=True,
    )


def page_clauses(doc) -> None:
    """Condiciones contractuales: las seis clausulas de la biblioteca CLM.

    Solo la monta el variant contract. Cada clausula va numerada y con su titulo
    en rojo para que se lea como articulado, no como parrafos sueltos.
    """
    page_break(doc)

    section_title(doc, "Condiciones contractuales")
    para(
        doc,
        "Las condiciones que siguen forman parte inseparable del presente contrato y "
        "proceden de la biblioteca de cláusulas de Comexi.",
        size=9,
        color="7A848D",
        italic=True,
        space_after=10,
    )

    for index, (heading, paragraphs) in enumerate(CLAUSES, start=1):
        table = doc.add_table(rows=1, cols=2)
        table_no_borders(table)
        table_cell_margins(table, top=100, bottom=100, left=0, right=160)
        set_widths(table, [1.0, CONTENT_CM - 1.0])
        number, body = table.rows[0].cells

        shade(number, GREY_SOFT)
        number.vertical_alignment = WD_ALIGN_VERTICAL.TOP
        write(
            number,
            f"{index}.",
            size=11,
            bold=True,
            color=RED,
            align=WD_ALIGN_PARAGRAPH.CENTER,
        )

        shade(body, GREY_SOFT)
        cell_borders(body, left=("single", 12, RED))
        strip_cell(body)
        title = body.add_paragraph()
        title.paragraph_format.left_indent = Cm(0.3)
        title.paragraph_format.space_after = Pt(4)
        style_run(title.add_run(heading.upper()), size=9.5, bold=True, color=SLATE, spacing=14)
        for position, text in enumerate(paragraphs):
            item = body.add_paragraph()
            item.paragraph_format.left_indent = Cm(0.3)
            item.paragraph_format.space_after = Pt(
                0 if position == len(paragraphs) - 1 else 4
            )
            style_run(item.add_run(text), size=9, color=SLATE)

        keep_together(table)
        para(doc, space_after=6)


def page_signature(doc, variant: str = "proposal") -> None:
    contract = variant == "contract"
    # En el contrato no se fuerza pagina: las seis clausulas se desbordan a una
    # segunda pagina que ocupan solo a tercios, y con el salto ese hueco se queda
    # en blanco. Dejando fluir el cierre, el articulado y la firma comparten
    # pagina y el documento acaba lleno hasta el final.
    if not contract:
        page_break(doc)

    section_title(
        doc,
        "Resumen y condiciones generales" if contract else "Validez y condiciones generales",
    )
    for text in CONTRACT_VALIDITY if contract else VALIDITY:
        item = doc.add_paragraph()
        item.paragraph_format.left_indent = Cm(0.5)
        item.paragraph_format.space_after = Pt(3)
        style_run(item.add_run("· "), size=9.5, bold=True, color=RED)
        style_run(item.add_run(text), size=9)
    para(doc, space_after=10)

    if not contract:
        _next_steps_section(doc)

    para(
        doc,
        f"Para cualquier duda sobre {'este contrato' if contract else 'esta propuesta'}: "
        f"{OPPORTUNITY['owner']}, "
        f"responsable comercial de Comexi para la cuenta {ACCOUNT['name']}. "
        f"Referencia interna de la operación: oferta {QUOTE['number']}, caso "
        f"{CASE['number']}, activo {ASSET['name']}.",
        size=9,
        color="7A848D",
        italic=True,
        space_after=26,
    )

    signature = doc.add_table(rows=2, cols=2)
    table_no_borders(signature)
    table_cell_margins(signature, top=60, bottom=200, left=0, right=160)
    set_widths(signature, [8.5, 8.5])
    labels = [
        ("Por Comexi Group Industries, S.A.U.", OPPORTUNITY["owner"]),
        (f"Por {ACCOUNT['name']}", CASE["contact_name"]),
    ]
    for index, (heading, name) in enumerate(labels):
        top = signature.rows[0].cells[index]
        write(top, heading, size=8, bold=True, color=RED, caps=True)
        bottom = signature.rows[1].cells[index]
        cell_borders(bottom, top=("single", 6, SLATE))
        write(bottom, f"{name} · Fecha:", size=8.5, color="7A848D")


def _next_steps_section(doc) -> None:
    """Los cuatro pasos posteriores a la aceptacion. Solo en la propuesta."""
    section_title(doc, "Siguientes pasos")
    steps = doc.add_table(rows=len(NEXT_STEPS), cols=3)
    table_no_borders(steps)
    table_cell_margins(steps, top=80, bottom=80, left=0, right=140)
    set_widths(steps, [1.1, 5.2, CONTENT_CM - 6.3])
    for index, (heading, text) in enumerate(NEXT_STEPS):
        row = steps.rows[index]
        no_split(row)
        number, label, body = row.cells
        shade(number, RED)
        number.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        write(
            number,
            str(index + 1),
            size=13,
            bold=True,
            color=WHITE,
            align=WD_ALIGN_PARAGRAPH.CENTER,
        )
        for cell in (label, body):
            shade(cell, GREY_SOFT)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        write(label, heading, size=9.5, bold=True, color=SLATE)
        write(body, text, size=9)
        if index < len(NEXT_STEPS) - 1:
            spacer = steps.rows[index]
            for cell in spacer.cells:
                cell_borders(cell, bottom=("single", 12, WHITE))
    para(doc, space_after=10)


# ---------------------------------------------------------------------------
# Documento
# ---------------------------------------------------------------------------


def configure(doc) -> None:
    normal = doc.styles["Normal"]
    normal.font.name = BODY_FONT
    normal.font.size = Pt(9.5)
    normal.font.color.rgb = RGBColor.from_string(SLATE)
    normal.paragraph_format.space_after = Pt(0)
    normal.paragraph_format.line_spacing = 1.15
    # Word usa rFonts/@w:eastAsia y @w:cs para tramos no latinos; sin fijarlos, el
    # convertidor a PDF puede caer en una fuente distinta a media linea.
    rpr = normal.element.get_or_add_rPr()
    fonts = rpr.find(qn("w:rFonts"))
    if fonts is None:
        fonts = OxmlElement("w:rFonts")
        rpr.insert(0, fonts)
    for attribute in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"):
        fonts.set(qn(attribute), BODY_FONT)

    section = doc.sections[0]
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.left_margin = Cm(2.0)
    section.right_margin = Cm(2.0)
    section.top_margin = Cm(2.5)
    section.bottom_margin = Cm(1.8)
    section.header_distance = Cm(1.0)
    section.footer_distance = Cm(0.8)


# Cifras y terminos que no pueden aparecer en un documento que se envia al cliente.
# La propuesta nacio con un anexo de escandallo y con el margen colado en la seccion de
# aprobacion; esta lista es el guardarrail para que no vuelva a pasar al anadir filas.
FORBIDDEN = [
    "margen",
    "escandallo",
    "coste",
    "uso interno",
    "no enviar",
    "ralf",
    "riesgo país",
    "comisión de representante",
    "11.465,56",  # coste total escandallado
    "3.856,62",  # margen absoluto
    "28,58",  # margen sobre venta
    "1.225,77",  # comision del representante
]


def assert_client_safe(doc) -> None:
    """Falla si el documento contiene datos que no debe ver el cliente."""
    text = " ".join(
        node.text for node in doc.element.body.iter(qn("w:t")) if node.text
    ).lower()
    found = sorted({term for term in FORBIDDEN if term in text})
    if found:
        raise AssertionError(
            "El documento se envia al cliente y contiene datos internos: "
            + ", ".join(found)
        )


def build(output: Path, variant: str = "proposal") -> None:
    for path in (LOGO, MACHINERY / "MAQ-S2-DS.jpg"):
        if not path.exists():
            raise FileNotFoundError(f"Falta la imagen {path}")
    for filename, _ in SCOPE_IMAGES:
        if not (PRODUCTS / filename).exists():
            raise FileNotFoundError(f"Falta la ficha de producto {PRODUCTS / filename}")

    contract = variant == "contract"
    reset_sections()

    doc = Document()
    configure(doc)
    build_header_footer(
        doc.sections[0],
        title=(
            f"Contrato de retrofit · Oferta {QUOTE['number']} · {QUOTE['date']}"
            if contract
            else None
        ),
        pages="8" if contract else "7",
    )

    page_cover(doc, variant)
    page_context(doc)
    page_viability(doc)
    page_scope(doc)
    page_economics(doc)
    page_conditions(doc)
    if contract:
        page_clauses(doc)
    page_signature(doc, variant)

    properties = doc.core_properties
    properties.title = (
        f"Contrato de retrofit · Oferta {QUOTE['number']}"
        if contract
        else f"Propuesta de retrofit · Oferta {QUOTE['number']}"
    )
    properties.subject = f"{ACCOUNT['name']} · {ASSET['name']} · T100 - UPDATE PC"
    properties.author = "Comexi Group Industries, S.A.U."
    properties.category = (
        "Revenue Cloud · Contract Lifecycle Management"
        if contract
        else "Revenue Cloud · Document Generation"
    )

    assert_client_safe(doc)

    output.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(output))
    shown = output
    if output.is_relative_to(REPO_ROOT):
        shown = output.relative_to(REPO_ROOT)
    print(f"Plantilla generada: {shown}")
    print(f"  variant: {variant} | secciones: {_section_counter}")
    print(f"  tamano: {output.stat().st_size / 1024:.0f} KB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--variant",
        choices=["proposal", "contract", "all"],
        default="all",
        help="Documento a generar (por defecto los dos)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Ruta del .docx generado. Solo con un --variant concreto.",
    )
    args = parser.parse_args()

    if args.variant == "all":
        if args.output:
            parser.error("--output necesita un --variant concreto, no 'all'.")
        for variant, path in DEFAULT_OUTPUTS.items():
            build(path, variant)
        return

    build(args.output or DEFAULT_OUTPUTS[args.variant], args.variant)


if __name__ == "__main__":
    main()
