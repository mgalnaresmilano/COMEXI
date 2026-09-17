#!/usr/bin/env python3
"""Construye el documento de escenarios para la sesion de preventa de Comexi.

Genera COMEXI_Escenarios_Demo.docx en la raiz del workspace. No es el guion de
la demo reformateado: es el material de la presentacion que va ANTES de la demo,
escrito para que cada seccion se convierta en una tanda de slides. El guion de
operacion sigue siendo DEMO_SCRIPT_COMEXI.md.

    python3 scripts/build_comexi_presales_deck.py [--output RUTA]

La marca se importa de build_comexi_retrofit_proposal en vez de duplicarse. Si
manana cambia el rojo corporativo o la tipografia, cambia en un sitio y los tres
documentos (propuesta, contrato y este) se mueven juntos. De ahi que aqui no haya
ni una constante de color.

OJO con el guardarrail: la propuesta tiene assert_client_safe, que prohibe la
palabra coste, margen, escandallo, RALF o comision de representante. Aqui NO se
aplica, y no es un olvido. La propuesta viaja a Roberts Mart, el cliente final de
Comexi, y esos numeros son los de Comexi. Este documento lo lee Comexi, y el
escandallo, los uplifts y los margenes 40/20/10 son su propio proceso: son
justamente lo que hay que demostrar que Revenue Cloud reproduce. Lo que no puede
colarse aqui es otra cosa, nombres de API y detalles de construccion, y de eso se
encarga assert_no_build_detail().

Las catorce escenas del guion se agrupan en cinco bloques mas un cierre. La
agrupacion sigue el recorrido del cliente, no el orden de construccion, porque en
una slide el ciclo se entiende y "escena 7" no dice nada.

Contenido, y de donde sale cada cosa:
  - Dolores D1-D13, prioridades y estadisticas: canvas de Discovery
    comexi-discovery-revenue-cloud.canvas.tsx (sesion del 4 ago 2026).
  - Cifras de la oferta, el contrato y el pedido: la org comexi, no la ficha
    tecnica del guion. La ficha conserva las cifras que se observaron en sesion
    (6.955,32 EUR con un 5% de descuento) y la oferta construida cierra en
    15.322,18 EUR con un 11,15% mezclado. Manda lo que se va a proyectar.

Imagenes: el logo lo pone la cabecera importada; la portada usa la foto de la
S2 DS de COMEXI_MachineryImages.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from docx import Document
from docx.enum.table import WD_ALIGN_VERTICAL
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Cm, Pt

from build_comexi_retrofit_proposal import (
    CONTENT_CM,
    GREY_LINE,
    GREY_SOFT,
    MACHINERY,
    RED,
    RED_SOFT,
    SLATE,
    WHITE,
    build_header_footer,
    cell_borders,
    configure,
    kv_table,
    keep_together,
    page_break,
    para,
    repeat_header,
    reset_sections,
    row_height,
    section_title,
    set_widths,
    shade,
    strip_cell,
    style_run,
    table_cell_margins,
    table_no_borders,
    trimmed,
    write,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = REPO_ROOT.parent / "COMEXI_Escenarios_Demo.docx"

MUTED = "7A848D"
FAINT = "9AA3AA"

SESSION_DATE = "16 de septiembre de 2026"
DISCOVERY_DATE = "4 de agosto de 2026"


# ---------------------------------------------------------------------------
# Helpers propios. Todo lo demas viene de la propuesta.
# ---------------------------------------------------------------------------


def label(doc, text: str, space_before: int = 8) -> None:
    """Rotulo rojo en versalitas que abre cada pieza de un bloque."""
    para(
        doc,
        text,
        size=8,
        bold=True,
        color=RED,
        caps=True,
        spacing=30,
        space_before=space_before,
        space_after=2,
    )


def bullets(doc, items, size: float = 9.5) -> None:
    """Lista con guion rojo y sangria francesa.

    No se usa el estilo List Bullet de Word: arrastra su propia fuente y su propio
    color y rompe la tipografia del resto del documento.
    """
    for text in items:
        paragraph = doc.add_paragraph()
        paragraph.paragraph_format.left_indent = Cm(0.55)
        paragraph.paragraph_format.first_line_indent = Cm(-0.55)
        paragraph.paragraph_format.space_after = Pt(3)
        style_run(paragraph.add_run("—  "), size=size, bold=True, color=RED)
        style_run(paragraph.add_run(text), size=size)


def stat_strip(doc, items) -> None:
    """Fila de cifras grandes: el numero en rojo y su rotulo debajo."""
    table = doc.add_table(rows=1, cols=len(items))
    table_no_borders(table)
    table_cell_margins(table, top=80, bottom=80, left=60, right=60)
    width = CONTENT_CM / len(items)
    set_widths(table, [width] * len(items))
    row = table.rows[0]
    row_height(row, 1.7)
    for cell, (number, caption) in zip(row.cells, items):
        shade(cell, GREY_SOFT)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        strip_cell(cell)
        top = cell.add_paragraph()
        top.alignment = WD_ALIGN_PARAGRAPH.CENTER
        top.paragraph_format.space_after = Pt(1)
        style_run(top.add_run(number), size=17, bold=True, color=RED)
        bottom = cell.add_paragraph()
        bottom.alignment = WD_ALIGN_PARAGRAPH.CENTER
        bottom.paragraph_format.space_after = Pt(0)
        bottom.paragraph_format.line_spacing = 1
        style_run(bottom.add_run(caption), size=8, color=SLATE)
    keep_together(table)
    para(doc, space_after=6)


def pain_card(doc, code: str, title: str, evidence: str, timestamp: str) -> None:
    """Tarjeta de dolor: codigo en un cuadro rojo y el cuerpo a la derecha."""
    table = doc.add_table(rows=1, cols=2)
    table_no_borders(table)
    table_cell_margins(table, top=90, bottom=90, left=0, right=0)
    set_widths(table, [1.55, CONTENT_CM - 1.55])
    badge, body = table.rows[0].cells

    shade(badge, RED)
    badge.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    write(badge, code, size=12, bold=True, color=WHITE, align=WD_ALIGN_PARAGRAPH.CENTER)

    shade(body, GREY_SOFT)
    strip_cell(body)
    heading = body.add_paragraph()
    heading.paragraph_format.left_indent = Cm(0.4)
    heading.paragraph_format.space_after = Pt(2)
    style_run(heading.add_run(title), size=10, bold=True, color=SLATE)

    text = body.add_paragraph()
    text.paragraph_format.left_indent = Cm(0.4)
    text.paragraph_format.space_after = Pt(2)
    style_run(text.add_run(evidence), size=9, color=SLATE)

    mark = body.add_paragraph()
    mark.paragraph_format.left_indent = Cm(0.4)
    mark.paragraph_format.space_after = Pt(0)
    style_run(mark.add_run(f"Sesión de Discovery · {timestamp}"), size=7.5, color=FAINT)

    keep_together(table)
    para(doc, space_after=5)


def impact_heading(doc, text: str, note: str) -> None:
    """Separador de grupo de impacto dentro de la seccion de dolores."""
    paragraph = para(doc, space_before=6, space_after=3)
    style_run(paragraph.add_run(text.upper()), size=9, bold=True, color=SLATE, spacing=25)
    style_run(paragraph.add_run(f"   {note}"), size=8.5, color=MUTED, italic=True)


def block_header(doc, number: str, title: str, scenes: str, pains: str) -> None:
    """Banda roja que abre cada bloque de la demo.

    El ultimo bloque se rotula "CIERRE" y no "BLOQUE Cierre": no es el sexto de una
    serie, es el remate, y en la slide se lee como tal.
    """
    table = doc.add_table(rows=1, cols=1)
    table_no_borders(table)
    table_cell_margins(table, top=150, bottom=150, left=220, right=220)
    set_widths(table, [CONTENT_CM])
    cell = table.rows[0].cells[0]
    shade(cell, RED)
    strip_cell(cell)

    eyebrow = cell.add_paragraph()
    eyebrow.paragraph_format.space_after = Pt(2)
    rubric = number if number.isalpha() else f"BLOQUE {number}"
    style_run(eyebrow.add_run(rubric.upper()), size=8.5, bold=True, color=WHITE, spacing=40)

    heading = cell.add_paragraph()
    heading.paragraph_format.space_after = Pt(3)
    heading.paragraph_format.line_spacing = 1
    style_run(heading.add_run(title), size=15, bold=True, color=WHITE)

    meta = cell.add_paragraph()
    meta.paragraph_format.space_after = Pt(0)
    style_run(meta.add_run(f"{scenes}   ·   Ataca {pains}"), size=8.5, color="FBD2DB")

    keep_together(table)
    para(doc, space_after=4)


def message_box(doc, text: str) -> None:
    """El mensaje que se tiene que llevar el cliente, destacado."""
    table = doc.add_table(rows=1, cols=2)
    table_no_borders(table)
    table_cell_margins(table, top=120, bottom=120, left=0, right=0)
    set_widths(table, [0.12, CONTENT_CM - 0.12])
    bar, body = table.rows[0].cells
    shade(bar, RED)
    shade(body, RED_SOFT)
    strip_cell(body)
    paragraph = body.add_paragraph()
    paragraph.paragraph_format.left_indent = Cm(0.4)
    paragraph.paragraph_format.space_after = Pt(0)
    style_run(paragraph.add_run(text), size=10, bold=True, color=SLATE)
    keep_together(table)
    para(doc, space_after=5)


def contrast(doc, today: str, tomorrow: str) -> None:
    """Dos columnas: como es hoy y como queda. El cierre de cada bloque."""
    table = doc.add_table(rows=1, cols=2)
    table_no_borders(table)
    table_cell_margins(table, top=110, bottom=110, left=160, right=160)
    half = CONTENT_CM / 2
    set_widths(table, [half, half])
    left, right = table.rows[0].cells

    for cell, heading, text, color in (
        (left, "Hoy", today, MUTED),
        (right, "Con Revenue Cloud", tomorrow, SLATE),
    ):
        shade(cell, GREY_SOFT if cell is left else RED_SOFT)
        cell_borders(cell, top=("single", 8, GREY_LINE if cell is left else RED))
        strip_cell(cell)
        top = cell.add_paragraph()
        top.paragraph_format.space_after = Pt(2)
        style_run(
            top.add_run(heading.upper()),
            size=7.5,
            bold=True,
            color=MUTED if cell is left else RED,
            spacing=30,
        )
        bottom = cell.add_paragraph()
        bottom.paragraph_format.space_after = Pt(0)
        style_run(bottom.add_run(text), size=9, color=color)

    keep_together(table)
    para(doc, space_after=6)


def grid_table(doc, headers, rows, widths) -> None:
    """Tabla con cabecera roja y filas zebra. Para las matrices del documento."""
    table = doc.add_table(rows=len(rows) + 1, cols=len(headers))
    table_no_borders(table)
    table_cell_margins(table, top=70, bottom=70, left=120, right=120)
    set_widths(table, widths)

    head = table.rows[0]
    row_height(head, 0.72)
    repeat_header(head)
    for cell, text in zip(head.cells, headers):
        shade(cell, RED)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        write(cell, text, size=8, bold=True, color=WHITE, caps=True)

    for index, values in enumerate(rows):
        row = table.rows[index + 1]
        fill = WHITE if index % 2 else GREY_SOFT
        for cell, text in zip(row.cells, values):
            shade(cell, fill)
            cell.vertical_alignment = WD_ALIGN_VERTICAL.TOP
            cell_borders(cell, bottom=("single", 4, GREY_LINE))
            write(cell, text, size=8.5)

    para(doc, space_after=6)


# ---------------------------------------------------------------------------
# Contenido
# ---------------------------------------------------------------------------


def page_cover(doc) -> None:
    para(doc, space_after=2)
    para(
        doc,
        f"Sesión de escenarios · {SESSION_DATE}",
        size=10,
        bold=True,
        color=RED,
        caps=True,
        spacing=40,
        space_after=2,
    )
    para(doc, "SERVICIO Y RETROFIT", size=30, bold=True, color=SLATE, space_after=0)
    para(
        doc,
        "Lo que os vamos a enseñar hoy, y qué dolor resuelve cada cosa",
        size=13,
        color=MUTED,
        space_after=10,
    )

    picture = doc.add_paragraph()
    picture.alignment = WD_ALIGN_PARAGRAPH.CENTER
    picture.paragraph_format.space_after = Pt(2)
    picture.paragraph_format.line_spacing = 1
    picture.add_run().add_picture(trimmed(MACHINERY / "MAQ-S2-DS.jpg"), width=Cm(13.0))
    para(
        doc,
        "Comexi S2 DS (antic Proslit S2 DS) · Activo MSC000600 · "
        "instalada en 2015 en Leeds (United Kingdom)",
        size=8,
        color=FAINT,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        italic=True,
        space_after=12,
    )

    kv_table(
        doc,
        [
            ("Origen", f"Sesión de Discovery del {DISCOVERY_DATE} · 1 h 16 min"),
            ("Hilo de la demo", "Caso 174535 · Roberts Mart Co Ltd (Leeds, UK)"),
            ("Retrofit", "T100 - UPDATE PC · migración del PC de línea a Windows 11"),
            ("Alcance de hoy", "Del caso de servicio al pedido descompuesto y facturable"),
        ],
        label_cm=4.6,
    )

    banner = doc.add_table(rows=1, cols=3)
    table_no_borders(banner)
    table_cell_margins(banner, top=140, bottom=140, left=160, right=160)
    third = CONTENT_CM / 3
    set_widths(banner, [third, third, third])
    row = banner.rows[0]
    row_height(row, 1.3)
    for cell, (number, caption) in zip(
        row.cells,
        [("6", "bloques"), ("13", "dolores atacados"), ("3", "prioridades cubiertas")],
    ):
        shade(cell, RED)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        strip_cell(cell)
        top = cell.add_paragraph()
        top.alignment = WD_ALIGN_PARAGRAPH.CENTER
        top.paragraph_format.space_after = Pt(0)
        top.paragraph_format.line_spacing = 1
        style_run(top.add_run(number), size=18, bold=True, color=WHITE)
        bottom = cell.add_paragraph()
        bottom.alignment = WD_ALIGN_PARAGRAPH.CENTER
        bottom.paragraph_format.space_after = Pt(0)
        bottom.paragraph_format.line_spacing = 1
        style_run(bottom.add_run(caption.upper()), size=8, color="FBD2DB", spacing=30)

    para(
        doc,
        "Cada bloque de este documento está escrito para convertirse en una tanda "
        "de slides: el dolor, lo que se verá en pantalla, la capacidad que lo "
        "sostiene y el mensaje.",
        size=8.5,
        color=FAINT,
        align=WD_ALIGN_PARAGRAPH.CENTER,
        italic=True,
        space_before=8,
    )


def page_today(doc) -> None:
    page_break(doc)
    section_title(doc, "Dónde estáis hoy")

    para(
        doc,
        "Comexi vende retrofits sobre máquinas que lleva instaladas desde los años "
        "noventa. El ciclo completo —catálogo, configuración, escandallo, precio, "
        "oferta y registro de pedidos— vive en un Google Sheets de doce pestañas, "
        "el LAUNCHER V8.4, más dos Google Docs. En Salesforce solo queda un enlace "
        "pegado en un post del caso.",
        space_after=4,
    )
    para(
        doc,
        "Funciona. Lo hemos visto funcionar en la sesión, y funciona porque hay gente "
        "que lo sostiene. El problema no es que la hoja calcule mal: es que todo lo "
        "que hay alrededor —la trazabilidad, la escala, el gobierno del dato y la "
        "capacidad de poner inteligencia encima— no cabe en una hoja.",
        space_after=8,
    )

    stat_strip(
        doc,
        [
            ("12+", "pestañas en el\nLauncher V8.4"),
            ("25", "pasos manuales\nen el ciclo"),
            ("3", "personas de\ncuello de botella"),
            ("113", "retrofits en\ncatálogo"),
            ("80%", "retrofits que no\nnecesitan ingeniería"),
        ],
    )

    para(
        doc,
        "Ese 80% es la cifra que más duele: ocho de cada diez retrofits no necesitan "
        "ingeniería, pero el 100% pasa por back-office. Y la última fila de la derecha "
        "explica por qué la conversación sobre IA se atasca.",
        space_after=6,
    )

    table = doc.add_table(rows=1, cols=2)
    table_no_borders(table)
    table_cell_margins(table, top=140, bottom=140, left=0, right=0)
    set_widths(table, [0.12, CONTENT_CM - 0.12])
    bar, body = table.rows[0].cells
    shade(bar, RED)
    shade(body, RED_SOFT)
    strip_cell(body)
    quote = body.add_paragraph()
    quote.paragraph_format.left_indent = Cm(0.45)
    quote.paragraph_format.space_after = Pt(3)
    style_run(
        quote.add_run(
            "«Meter inteligencia artificial sobre un Excel es muy complicado, porque "
            "al final esto no va a estar conectando con todo el mundo que hay en el "
            "quote-to-cash.»"
        ),
        size=11,
        italic=True,
        color=SLATE,
    )
    attribution = body.add_paragraph()
    attribution.paragraph_format.left_indent = Cm(0.45)
    attribution.paragraph_format.space_after = Pt(0)
    style_run(attribution.add_run("Comexi · sesión de Discovery, 1:05:08"), size=8, color=MUTED)
    keep_together(table)
    para(doc, space_after=6)

    para(
        doc,
        "Lo que sigue son los trece dolores que recogimos, las tres cosas que pedisteis "
        "al final de la sesión y los seis bloques de demo con los que os vamos a "
        "responder. La demo no es un recorrido de producto: es vuestro caso 174535, "
        "de principio a fin.",
    )


def page_pains(doc) -> None:
    page_break(doc)
    section_title(doc, "Los trece dolores que recogimos")

    para(
        doc,
        "Salen de la sesión del 4 de agosto, cruzando la transcripción con lo que se "
        "vio en pantalla. Van agrupados por impacto, y cada uno lleva el minuto exacto "
        "en el que aparece, para que cualquiera pueda comprobarlo.",
        space_after=6,
    )

    impact_heading(doc, "Impacto crítico", "los cuatro que la demo ataca de frente")
    pain_card(
        doc,
        "D1",
        "El ciclo de cotización vive fuera del CRM",
        "Configurador, escandallo, precio y oferta están en un Google Sheets de doce "
        "pestañas y en Google Docs. En Salesforce solo queda un enlace pegado en un "
        "post del caso.",
        "6:26 – 50:42, 1:05:08",
    )
    pain_card(
        doc,
        "D2",
        "El vendedor no puede ofertar solo",
        "Tres personas de back-office hacen de intermediarias entre vendedores y "
        "oficina técnica. El 80% de los retrofits no necesita ingeniería, pero el "
        "100% pasa por back-office.",
        "27:13 – 31:16",
    )
    pain_card(
        doc,
        "D3",
        "Aprobaciones verbales sin histórico",
        "Por debajo del margen mínimo hace falta aprobación, y se pide «verbalmente, "
        "o con un chat de Hangouts, o con un WhatsApp, o una llamada». No queda "
        "registro de la negociación ni de las propuestas de descuento.",
        "42:38 – 43:26",
    )
    pain_card(
        doc,
        "D8",
        "Viabilidad técnica manual sobre datos dispersos",
        "Hay que comprobar si el retrofit estándar encaja en una máquina que puede "
        "tener 23 años. Las nomenclaturas están repartidas entre SAP, el PLM y hojas "
        "en Drive. Cuanto más antigua la máquina, más se multiplican los costes "
        "reales, por tres o por cuatro.",
        "21:19 – 23:44, 31:16 – 32:18",
    )

    page_break(doc)
    impact_heading(doc, "Impacto alto", "aparecen todos en la demo de hoy")
    pain_card(
        doc,
        "D4",
        "No saben dar precios desglosados ni add-ons",
        "El retrofit se oferta como paquete con un precio único. «Lo que no está "
        "pensado y últimamente van pidiendo es poder dar precios desglosados»: "
        "opción base más add-on, con el control de temperatura de tinta a 3.600 € "
        "como ejemplo citado.",
        "59:18 – 1:00:06",
    )
    pain_card(
        doc,
        "D5",
        "Versionado manual y control de acceso difuso",
        "Si el cliente pide cambios se genera un documento nuevo y el vendedor teclea "
        "a mano el número de versión. El documento de oferta que se mostró en sesión "
        "estaba compartido con 189 personas.",
        "46:17 – 49:23",
    )
    pain_card(
        doc,
        "D6",
        "Doble entrada en SAP y conversión manual a pedido",
        "La oferta se procesa también en SAP en paralelo y, después, una persona entra "
        "en SAP, mira la oferta y la transforma en pedido a mano.",
        "52:00 – 53:27",
    )
    pain_card(
        doc,
        "D7",
        "Documento contractual duplicado para poder firmar",
        "La oferta no tiene campo de firma, así que se genera un segundo documento, el "
        "contrato de viabilidad, un 99% igual a la oferta, y ese es el que se firma.",
        "50:46 – 51:57",
    )
    pain_card(
        doc,
        "D9",
        "Sin dashboards ni KPIs",
        "Están construyendo a mano el registro de ofertas y el de pedidos precisamente "
        "para poder tener dashboards. Visibilidad y transparencia fue el primer factor "
        "de éxito mencionado.",
        "1:00:27 – 1:01:18",
    )
    pain_card(
        doc,
        "D12",
        "Riesgo de gobierno del dato y coste de la IA",
        "Usan Gemini directo desde la hoja. Los controles de información confidencial "
        "existen dentro de Google, pero «cuando utilizamos otras herramientas perdemos "
        "el control». Arrastran además una compra previa de licencias que no llegó a "
        "funcionar, de ahí el «pasito a pasito».",
        "1:08:46 – 1:15:44",
    )

    page_break(doc)
    impact_heading(doc, "Impacto medio", "quedan cubiertos, aunque no protagonicen")
    pain_card(
        doc,
        "D10",
        "Catálogos separados por tipo de negocio",
        "El catálogo de retrofits (113 productos) está en la hoja; la máquina nueva se "
        "configura en el PLM Windchill con unas 15.000 referencias; los servicios puros "
        "«de momento no los tenemos catalogados».",
        "15:06 – 18:48",
    )
    pain_card(
        doc,
        "D11",
        "Precios y costes en hojas descargadas de SAP",
        "El precio base y los costes están descargados en una hoja. El coste hora de "
        "cada técnico lo actualiza Finanzas una vez al año y no varía durante el "
        "ejercicio; los costes de material se leen de SAP.",
        "38:21 – 39:01",
    )
    pain_card(
        doc,
        "D13",
        "Gestión de cambios post-pedido sin proceso",
        "Si el cliente modifica o cancela parte del alcance después de confirmar el "
        "pedido no hay protocolo: se envían correos avisando e improvisando.",
        "56:59 – 57:57",
    )


def page_priorities(doc) -> None:
    page_break(doc)
    section_title(doc, "Las tres cosas que pedisteis")

    para(
        doc,
        "Al final de la sesión os preguntamos qué tres elementos del proceso "
        "mejoraríais con mayor impacto. Estas tres respuestas son el esqueleto de la "
        "demo, y por eso aparecen aquí con vuestras palabras y no con las nuestras.",
        space_after=8,
    )

    priorities = [
        (
            "1",
            "Automatizar el estudio de viabilidad",
            "Con agéntica sobre los datos del caso, o como preestudio masivo sobre la "
            "base instalada. Hoy el 100% pasa por filtro humano.",
            "58:26",
            "Bloques 1 y de cierre",
        ),
        (
            "2",
            "Precios desglosados y add-ons",
            "Hoy el retrofit sale como paquete con un precio único. Piden poder decir "
            "«este es el precio básico, y el control de temperatura de tinta son "
            "3.600 € más».",
            "59:18",
            "Bloque 3",
        ),
        (
            "3",
            "Dashboards y KPIs",
            "Están construyendo a mano el registro de ofertas y el de pedidos "
            "precisamente para poder medir. Visibilidad y transparencia es su primer "
            "criterio de éxito.",
            "1:00:27",
            "Bloque de cierre",
        ),
    ]

    for number, title, description, timestamp, where in priorities:
        table = doc.add_table(rows=1, cols=2)
        table_no_borders(table)
        table_cell_margins(table, top=130, bottom=130, left=0, right=0)
        set_widths(table, [2.1, CONTENT_CM - 2.1])
        badge, body = table.rows[0].cells

        shade(badge, RED)
        badge.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        strip_cell(badge)
        top = badge.add_paragraph()
        top.alignment = WD_ALIGN_PARAGRAPH.CENTER
        top.paragraph_format.space_after = Pt(0)
        top.paragraph_format.line_spacing = 1
        style_run(top.add_run(number), size=22, bold=True, color=WHITE)
        bottom = badge.add_paragraph()
        bottom.alignment = WD_ALIGN_PARAGRAPH.CENTER
        bottom.paragraph_format.space_after = Pt(0)
        bottom.paragraph_format.line_spacing = 1
        style_run(bottom.add_run("PRIORIDAD"), size=6.5, color="FBD2DB", spacing=20)

        shade(body, GREY_SOFT)
        strip_cell(body)
        heading = body.add_paragraph()
        heading.paragraph_format.left_indent = Cm(0.45)
        heading.paragraph_format.space_after = Pt(2)
        style_run(heading.add_run(title), size=11, bold=True, color=SLATE)
        text = body.add_paragraph()
        text.paragraph_format.left_indent = Cm(0.45)
        text.paragraph_format.space_after = Pt(3)
        style_run(text.add_run(description), size=9, color=SLATE)
        footer = body.add_paragraph()
        footer.paragraph_format.left_indent = Cm(0.45)
        footer.paragraph_format.space_after = Pt(0)
        style_run(footer.add_run(f"Sesión · {timestamp}"), size=7.5, color=FAINT)
        style_run(footer.add_run("      Lo veréis en: "), size=7.5, color=FAINT)
        style_run(footer.add_run(where), size=7.5, bold=True, color=RED)

        keep_together(table)
        para(doc, space_after=6)


def page_matrix(doc) -> None:
    page_break(doc)
    section_title(doc, "Cómo lo resuelve Revenue Cloud")

    para(
        doc,
        "Esta es la traducción, pestaña a pestaña. La columna de la izquierda es lo "
        "que hacéis hoy y con qué; la de la derecha, la funcionalidad estándar que lo "
        "sustituye. No hay desarrollo a medida detrás de ninguna fila: todo es "
        "configuración de producto.",
        space_after=6,
    )

    grid_table(
        doc,
        ["Función", "Hoy", "Revenue Cloud"],
        [
            (
                "Catálogo de 113 retrofits",
                "Pestaña SYS_Resume y fichas en Drive",
                "Product Catalog Management: catálogo, categorías, clasificaciones y bundles",
            ),
            (
                "Configurador de opciones",
                "Pestañas ETO_Options y ETO_Codes",
                "Product Configurator con reglas de restricción en tiempo real",
            ),
            (
                "Estudio de viabilidad",
                "Ingeniería, SAP, PLM y hojas en Drive",
                "Base instalada como activo + cualificación de producto + Agentforce",
            ),
            (
                "Escandallo",
                "Pestaña ALL_Escandall",
                "Salesforce Pricing: procedura configurable con uplifts, riesgos y márgenes",
            ),
            (
                "Coste de material y de hora",
                "Descarga de SAP a una hoja",
                "Cost books como fuente de coste, sincronizables con SAP",
            ),
            (
                "Precio desglosado y add-ons",
                "«Lo que no está pensado»",
                "Grupos de líneas y add-on como producto propio con su precio",
            ),
            (
                "Calculadora de descuento",
                "Fórmulas en la hoja",
                "Deal guidance: avisa del coste de la firma antes de prometer el descuento",
            ),
            (
                "Aprobación del descuento",
                "Voz, Hangouts, WhatsApp o llamada",
                "Aprobaciones nativas por umbral, con firma, fecha, persona y motivo",
            ),
            (
                "Oferta multiidioma",
                "Menú del Launcher hacia Google Docs",
                "Generación de documento desde plantilla con los datos vivos de la oferta",
            ),
            (
                "Versionado de la oferta",
                "Número tecleado a mano",
                "Versionado automático con histórico y comparativa",
            ),
            (
                "Contrato de viabilidad",
                "Segundo documento, 99% igual",
                "Contrato nacido de la oferta, con cláusulas de biblioteca y su articulado",
            ),
            (
                "Oferta a pedido y salida a SAP",
                "Una persona reintroduce en SAP",
                "Pedido desde la oferta y descomposición: material a SAP, intervención a operaciones",
            ),
            (
                "Seguimiento del anticipo",
                "Correo a Finanzas",
                "Hito de facturación con dependencia real sobre el arranque de ingeniería",
            ),
            (
                "Recomendación de producto",
                "Función de IA en una celda",
                "Agentforce sobre datos estructurados, con Trust Layer y agnóstico de modelo",
            ),
            (
                "Dashboards y KPIs",
                "Registro construido a mano",
                "Informes y cuadros de mando nativos sobre oferta, pedido y base instalada",
            ),
        ],
        widths=[4.1, 5.0, CONTENT_CM - 9.1],
    )


def demo_block(
    doc,
    number: str,
    title: str,
    scenes: str,
    pains: str,
    intro: str,
    pain_quote: str,
    seen,
    capabilities: str,
    message: str,
    today: str,
    tomorrow: str,
    new_page: bool = True,
) -> None:
    """Un bloque de la demo con sus cinco piezas fijas: el esqueleto de una slide."""
    if new_page:
        page_break(doc)
    block_header(doc, number, title, scenes, pains)

    para(doc, intro, space_after=2)

    label(doc, "El dolor que ataca")
    para(doc, pain_quote, size=9.5, italic=True, color=MUTED, space_after=2)

    label(doc, "Qué vais a ver en pantalla")
    bullets(doc, seen)

    label(doc, "Qué lo sostiene")
    para(doc, capabilities, size=9, color=MUTED, space_after=2)

    label(doc, "El mensaje")
    message_box(doc, message)

    contrast(doc, today, tomorrow)


def page_blocks(doc) -> None:
    page_break(doc)
    section_title(doc, "Los cinco bloques de la demo")

    para(
        doc,
        "Las catorce escenas del guión se agrupan en cinco bloques que siguen el "
        "recorrido del retrofit, más un cierre. Todo ocurre sobre el mismo hilo: el "
        "caso 174535 de Roberts Mart sobre la máquina MSC000600. No se abre ni una "
        "pantalla que no venga de la anterior.",
        space_after=6,
    )

    grid_table(
        doc,
        ["Bloque", "De qué va", "Dolores"],
        [
            ("1", "De la incidencia al veredicto de viabilidad", "D8, D1"),
            ("2", "El vendedor cotiza solo", "D2, D1, D10"),
            ("3", "El escandallo y la firma del descuento", "D11, D3, D4"),
            ("4", "Un solo documento, de la oferta al contrato", "D5, D7"),
            ("5", "El pedido se descompone solo", "D6, D13"),
            ("Cierre", "Visibilidad hoy, proactividad después", "D9, D12"),
        ],
        widths=[2.2, CONTENT_CM - 5.6, 3.4],
    )

    demo_block(
        doc,
        "1",
        "De la incidencia al veredicto de viabilidad",
        "Escenas 1 y 2",
        "D8 y D1 · Prioridad 1",
        "El cliente escribe pidiendo actualizar el PC de su máquina. Hoy ahí empieza "
        "una ronda de consultas a ingeniería, a SAP y al PLM. Vamos a ver esa misma "
        "petición resolverse sola.",
        "«Hay que comprobar si el retrofit estándar encaja en una máquina que puede "
        "tener 23 años», con las nomenclaturas repartidas entre SAP, el PLM y hojas "
        "en Drive.",
        [
            "La máquina MSC000600 como objeto de primera clase, con su configuración "
            "instalada y su jerarquía de componentes. Deja de ser una matrícula en una "
            "celda: es la base sobre la que se calcula la viabilidad.",
            "El caso 174535 colgando de esa máquina, con la petición del cliente tal "
            "cual llegó: «PC + Win, actualitzem oferta W11».",
            "El agente lanzado desde el propio caso: devuelve la valoración, recomienda "
            "T100 - UPDATE PC y da un veredicto de viabilidad explicando el porqué.",
            "La prueba de que no se inventa nada: un código que no existe en el "
            "catálogo no puede recomendarse, por mucho que se le insista.",
        ],
        "Base instalada como activo · cualificación de producto · Agentforce sobre datos "
        "estructurados con Trust Layer.",
        "Vuestra prioridad número uno es lo primero que se ve, y funciona porque debajo "
        "hay datos estructurados y no una hoja.",
        "El 100% de las viabilidades pasa por filtro humano.",
        "El preestudio llega hecho al caso, con su traza y sin inventar códigos.",
        new_page=True,
    )

    demo_block(
        doc,
        "2",
        "El vendedor cotiza solo",
        "Escenas 3, 4 y 5",
        "D2, D1 y D10",
        "Con la viabilidad resuelta, el vendedor abre la oportunidad y configura. Sin "
        "pasar por las tres personas del back-office y sin salir de la pantalla.",
        "Tres personas de back-office hacen de intermediarias. «No hemos llegado al "
        "punto de que el vendedor lo pueda ofertar totalmente solo.»",
        [
            "Un botón en el caso crea la oportunidad de tipo retrofit, atada a la "
            "cuenta, a la máquina y al caso de origen, con sus cuatro secciones ya "
            "rellenas: máquina, viabilidad, alcance y económico. El historial del caso "
            "aparece volcado en su actividad.",
            "El configurador guiado: preguntas de negocio (número de CPUs GL, número de "
            "CUs) y opcionales (CPU Simotion, CU Sinamics, pupitre HMI, cambio de "
            "pantalla). Una combinación incompatible se bloquea con un mensaje legible, "
            "no con un error técnico.",
            "Vuestro planificador de intervención convertido en líneas de cotización: "
            "horas de montaje mecánico, instalación eléctrica y puesta en marcha, más "
            "el grupo de gastos —vuelo, taxi, hotel y dietas para Leeds— con el "
            "indicador de a cargo de quién va cada uno.",
            "Relanzar el proceso no duplica nada: ni oportunidad, ni oferta, ni "
            "actividades.",
        ],
        "Catálogo y bundles · configurador con reglas de restricción · agrupación de "
        "líneas de cotización.",
        "El back-office deja de ejecutar y pasa a atender excepciones. El vendedor "
        "responde preguntas de negocio y el sistema aplica la lógica técnica.",
        "Veinte minutos por ficha y tres intermediarios para el 100% de los casos.",
        "El vendedor no sale de la oferta, y el 80% sin ingeniería deja de hacer cola.",
    )

    demo_block(
        doc,
        "3",
        "El escandallo y la firma del descuento",
        "Escenas 6, 7 y 8",
        "D11, D3 y D4 · Prioridad 2",
        "Aquí está el miedo de fondo: perder la capacidad de calcular como calculáis "
        "hoy. Vamos a reproducir el escandallo entero, concepto a concepto, sin una "
        "línea de código de negocio.",
        "El margen se negocia «verbalmente, o con un chat de Hangouts, o con un "
        "WhatsApp, o una llamada», y no queda registro de la negociación ni de las "
        "propuestas de descuento.",
        [
            "El escandallo como procedura de precios configurable: coste de material del "
            "cost book, horas al valor que fija Finanzas (56 € el técnico, 30 € la "
            "manutención), uplift de garantía del 2,60%, RALF del 3,00%, riesgo por país "
            "y tecnología, comisión de representante del 8% y márgenes por concepto "
            "del 40, 20 y 10%.",
            "El precio desglosado que pedisteis: el retrofit base como grupo y el "
            "control de temperatura de tinta como línea aparte con sus 3.600 €. Y una "
            "alternativa de alcance para comparar escenarios en el mismo documento.",
            "El aviso antes de prometer: el descuento mezclado de la oferta es del "
            "11,15%, pero la línea del T100 lleva un 25%, y eso son dos firmas. El "
            "vendedor lo sabe antes de decírselo al cliente.",
            "La aprobación completa en vivo: enviar a aprobación, el registro pasa a "
            "pendiente, se firma el nivel de Manager con comentario, luego el de "
            "Director, y queda aprobado con las dos firmas en la traza.",
        ],
        "Procedura de precios configurable · cost books · matrices de ajuste y descuento "
        "por atributo · deal guidance · aprobaciones nativas encadenadas.",
        "Vuestro escandallo no es código, es configuración. Y el descuento deja de "
        "firmarse por WhatsApp sin dejar de ser rápido.",
        "El descuento mezclado esconde lo que pasa en cada línea, y la firma no deja rastro.",
        "El sistema caza el 25% oculto tras el 11,15% y cada firma queda auditada.",
    )

    demo_block(
        doc,
        "4",
        "Un solo documento, de la oferta al contrato",
        "Escenas 9 y 10",
        "D5 y D7",
        "Hoy generáis dos documentos casi idénticos y el segundo existe solo porque el "
        "primero no se puede firmar. Vamos a ver los dos salir del mismo hilo.",
        "«La oferta no tiene campo de firma, así que se genera un segundo documento, "
        "el contrato de viabilidad, un 99% igual a la oferta.» Y el de la sesión "
        "estaba compartido con 189 personas.",
        [
            "Un clic y sale la propuesta con marca Comexi: portada con la foto de la "
            "S2 DS, el caso que originó todo con la petición literal del cliente, el "
            "veredicto de viabilidad, las tres tablas de la oferta —producto, "
            "intervención y gastos— y el total de 15.322,18 EUR con su reparto entre "
            "máquina, mano de obra y gastos.",
            "Lo que el documento no lleva, que importa tanto como lo que lleva: ni "
            "coste, ni margen, ni comisión del representante. Eso se queda en casa. Lo "
            "único que se cuenta del circuito interno es que el descuento pasó por una "
            "firma, que es argumento de venta.",
            "El cliente pide un cambio y sale la versión 2: número, histórico y "
            "comparativa automáticos, sin teclear nada.",
            "Create Contract, y vuelve un contrato en borrador con los detalles ya "
            "escritos —origen, alcance, intervención y condiciones— y el documento "
            "contractual ya generado: las mismas páginas más una de condiciones, con "
            "seis cláusulas que salen de la biblioteca y quedan asociadas al contrato.",
        ],
        "Generación de documento en servidor · versionado de oferta · gestión del ciclo "
        "de vida del contrato con biblioteca de cláusulas.",
        "El contrato no se redacta: nace del hilo. El 99% que hoy se duplica a mano se "
        "copia solo, y el 1% que lo diferencia sale de la biblioteca, no del Word de "
        "nadie.",
        "Dos documentos, versión tecleada a mano y un fichero con 189 personas dentro.",
        "Un hilo, versionado automático y permisos por perfil en vez de compartición.",
    )

    demo_block(
        doc,
        "5",
        "El pedido se descompone solo",
        "Escenas 11 y 12",
        "D6 y D13",
        "El contrato se firma y empieza la parte que hoy obliga a reintroducir todo en "
        "SAP. Aquí no se teclea un solo dato.",
        "La oferta se procesa en SAP en paralelo y después «una persona entra en SAP, "
        "mira la oferta y la transforma en pedido» a mano.",
        [
            "Al firmar aparece el pedido, ya activado, con sus diez líneas, el mismo "
            "importe y el expediente del retrofit escrito: origen, alcance, "
            "intervención, anticipo y código de cliente en SAP.",
            "El plan de trabajo con nueve pasos en tres grupos: los códigos de material "
            "salen hacia SAP, la intervención se entrega a operaciones para planificarla "
            "y el anticipo del 30%, 4.596,65 EUR, se emite como hito de facturación.",
            "La regla que hoy vive en un correo, convertida en dependencia: el arranque "
            "de ingeniería está bloqueado. Se marca el cobro del anticipo como "
            "confirmado y ingeniería arranca en ese mismo momento. Operaciones, "
            "mientras tanto, sí puede ir reservando la ventana de intervención: no es "
            "un semáforo que lo para todo.",
            "Cerrada la instalación, la máquina refleja su nueva configuración. El PC "
            "con Windows 11 ya es base instalada, y la siguiente viabilidad se calcula "
            "sobre datos correctos.",
        ],
        "Descomposición del pedido y orquestación · hitos de facturación · actualización "
        "de la base instalada.",
        "Un pedido, tres destinos y ni un dato reintroducido. La condición de cobro "
        "deja de ser un correo y pasa a ser una dependencia que se ve bloquear y "
        "desbloquear en directo.",
        "Doble entrada en SAP y una persona convirtiendo ofertas en pedidos.",
        "La descomposición es configuración, y cada venta mejora el dato de la siguiente.",
    )

    demo_block(
        doc,
        "Cierre",
        "Visibilidad hoy, proactividad después",
        "Escenas 13 y 14",
        "D9 y D12 · Prioridad 3",
        "Las dos últimas pantallas son las que explican por qué merece la pena todo lo "
        "anterior: porque el dato queda estructurado.",
        "Están construyendo a mano el registro de ofertas y el de pedidos precisamente "
        "para poder medir. Visibilidad y transparencia fue el primer criterio de éxito "
        "que se mencionó.",
        [
            "Los cuadros de mando: tiempo medio de cotización, tasa de conversión, "
            "margen medio por familia, descuento medio, ofertas pendientes de aprobación "
            "y pipeline de retrofit por línea de máquina y país. El registro que estáis "
            "construyendo a mano, de serie.",
            "El agente recorriendo la base instalada, detectando qué máquinas están "
            "afectadas por la obsolescencia de un componente y proponiendo la campaña "
            "de retrofit con una oferta preconfigurada por máquina. Es el preestudio "
            "masivo que se pidió en la sesión.",
            "Sobre el gobierno del dato: el agente es agnóstico de modelo. Podéis seguir "
            "con Gemini si queréis, pero trabajando sobre datos de la plataforma, con "
            "control de lo que sale y coste previsible.",
        ],
        "Informes y cuadros de mando nativos · Agentforce sobre la base instalada con "
        "Trust Layer.",
        "Medir deja de ser un proyecto aparte y pasa a ser consecuencia de trabajar en "
        "la plataforma. Y el negocio de retrofit pasa de reactivo a proactivo.",
        "El registro se construye a mano para poder medir, y la IA vive fuera del dato.",
        "Los cuadros de mando salen del trabajo diario, y el agente sale a buscar negocio.",
    )


def page_coverage(doc) -> None:
    page_break(doc)
    section_title(doc, "Cobertura")

    para(
        doc,
        "Los trece dolores quedan atacados por los seis bloques, y las tres prioridades "
        "que pedisteis tienen bloque propio. Esta tabla existe para poder decir, sin "
        "rodeos, que no hemos elegido solo lo que nos convenía enseñar.",
        space_after=6,
    )

    grid_table(
        doc,
        ["Dolor", "Qué es", "Dónde se ve"],
        [
            ("D1", "El ciclo de cotización vive fuera del CRM", "Bloques 1 y 2"),
            ("D2", "El vendedor no puede ofertar solo", "Bloque 2"),
            ("D3", "Aprobaciones verbales sin histórico", "Bloque 3"),
            ("D4", "Sin precios desglosados ni add-ons", "Bloque 3"),
            ("D5", "Versionado manual y acceso difuso", "Bloque 4"),
            ("D6", "Doble entrada en SAP", "Bloque 5"),
            ("D7", "Documento contractual duplicado", "Bloque 4"),
            ("D8", "Viabilidad manual sobre datos dispersos", "Bloque 1"),
            ("D9", "Sin dashboards ni KPIs", "Cierre"),
            ("D10", "Catálogos separados por tipo de negocio", "Bloque 2"),
            ("D11", "Precios y costes en hojas de SAP", "Bloque 3"),
            ("D12", "Gobierno del dato y coste de la IA", "Cierre"),
            ("D13", "Cambios post-pedido sin proceso", "Bloque 5"),
        ],
        widths=[1.8, CONTENT_CM - 5.6, 3.8],
    )


def page_scope(doc) -> None:
    page_break(doc)
    section_title(doc, "Qué es nativo y qué está simulado")

    para(
        doc,
        "Preferimos decirlo antes de que lo preguntéis a mitad de demo. Todo lo que se "
        "ve es funcionalidad estándar configurada, sin desarrollo a medida de negocio. "
        "Hay cuatro puntos donde la demo simula, y conviene tenerlos claros.",
        space_after=6,
    )

    label(doc, "Nativo de verdad, sin atajos", space_before=2)
    bullets(
        doc,
        [
            "Catálogo, bundles y configurador con reglas de restricción.",
            "Escandallo completo como procedura de precios, con cost books, uplifts, "
            "riesgos, comisión y márgenes por concepto.",
            "Deal guidance y aprobaciones encadenadas con su histórico.",
            "Generación de la propuesta y del contrato, con versionado y biblioteca de "
            "cláusulas.",
            "Pedido desde la oferta, descomposición en plan de trabajo, dependencias "
            "entre pasos e hito de facturación del anticipo.",
            "Cuadros de mando y agente sobre la base instalada.",
        ],
    )

    label(doc, "Simulado o acotado en el entorno de demo")
    bullets(
        doc,
        [
            "La salida a SAP se ve como un paso de la descomposición con su código de "
            "material, pero no hay un SAP real conectado al otro lado. La integración "
            "es un proyecto en sí misma y depende de vuestro middleware actual.",
            "La firma electrónica necesita una conexión con el proveedor de firma que "
            "el entorno de demo no tiene. El botón está y el circuito es el real; hoy "
            "se enseña sin enviar a firmar.",
            "El catálogo es una selección representativa construida con lo que vimos en "
            "sesión, no los 113 retrofits. Cargarlos es una extracción de vuestra hoja, "
            "no un desarrollo.",
            "Los dos niveles de aprobación recaen en la misma persona para no consumir "
            "licencias del entorno. En vuestro caso serían dos perfiles distintos.",
        ],
    )

    para(
        doc,
        "Una nota sobre las cifras: el caso que se ve es el 174535 tal como lo "
        "observamos, pero la oferta se ha reconstruido con vuestro escandallo completo, "
        "incluyendo el add-on de temperatura de tinta y la intervención en Leeds. Por "
        "eso el total que aparece en pantalla no coincide con el de la hoja que nos "
        "enseñasteis: no es el mismo alcance.",
        size=9,
        color=MUTED,
        space_before=6,
        italic=True,
    )


def page_next(doc) -> None:
    page_break(doc)
    section_title(doc, "Lo que necesitamos saber de vosotros")

    para(
        doc,
        "De la sesión salieron preguntas que no pudimos cerrar y que condicionan cómo "
        "sería esto en vuestra casa, no en una demo. Son las que proponemos abordar "
        "después de ver las pantallas.",
        space_after=6,
    )

    grid_table(
        doc,
        ["Pregunta abierta", "Por qué importa"],
        [
            (
                "Roles y aprobaciones tras la reorganización de septiembre",
                "Define quién firma cada nivel de descuento y cómo quedan las cadenas",
            ),
            (
                "Volumen anual de ofertas de retrofit y tasa de conversión",
                "Es lo que calibra los indicadores y da la medida del retorno",
            ),
            (
                "Número medio de versiones por oferta y porcentaje renegociado",
                "Dimensiona cuánto pesa realmente el versionado manual de hoy",
            ),
            (
                "Cómo es la integración con SAP y quién la mantiene",
                "Determina el esfuerzo del único punto que hoy simulamos",
            ),
            (
                "Si facturáis en divisa local además de en euros",
                "Condiciona el diseño de las listas de precios",
            ),
            (
                "Los packs de servicio que hoy no están catalogados",
                "Son catálogo nuevo, y ahí hay negocio que hoy no se puede ofertar",
            ),
            (
                "Qué guardarraíles de IA necesitáis y qué licencias tenéis",
                "Marca el alcance realista del agente y el ritmo del despliegue",
            ),
        ],
        widths=[6.8, CONTENT_CM - 6.8],
    )


def page_annex(doc) -> None:
    page_break(doc)
    section_title(doc, "Anexo: el hilo de la demo")

    para(
        doc,
        "Todo lo que se ve hoy cuelga de estos datos. Sirve de chuleta durante la "
        "sesión y de referencia para quien no haya estado en el Discovery.",
        space_after=6,
    )

    kv_table(
        doc,
        [
            ("Cuenta", "Roberts Mart Co Ltd · Leeds, United Kingdom"),
            ("Representante", "Activo, con comisión del 8%"),
            ("Caso de servicio", "174535 · «PC + Win, actualitzem oferta W11»"),
            ("Máquina", "MSC000600 · Comexi S2 DS (antic Proslit S2 DS), instalada en 2015"),
            ("Componente obsoleto", "PC de línea con Windows 10 fuera de soporte"),
            ("Retrofit recomendado", "T100 - UPDATE PC, por obsolescencia"),
            ("Add-on", "Control de temperatura de tinta · 3.600 €"),
            ("Intervención", "Leeds · 6 semanas · 36 horas · gastos a cargo de Comexi"),
            ("Importe de la oferta", "15.322,18 EUR"),
            ("Descuento", "11,15% mezclado, con un 25% en la línea del T100"),
            ("Aprobación", "Dos niveles: Manager y Director de Servicio"),
            ("Anticipo", "30% · 4.596,65 EUR · pago a 30 días"),
            ("Garantía", "6 meses desde la aceptación"),
            ("Plan de trabajo", "9 pasos en 3 grupos: material, intervención y finanzas"),
        ],
        label_cm=5.0,
    )

    para(
        doc,
        "Los roles que se turnan en pantalla: agente de servicio, agente autónomo de "
        "viabilidad, vendedor de servicio, Manager y Director para las firmas, legal "
        "para el contrato, operaciones y finanzas para el pedido, y dirección de "
        "servicio para los indicadores.",
        size=9,
        color=MUTED,
        space_before=4,
        italic=True,
    )


# ---------------------------------------------------------------------------
# Guardarrail
# ---------------------------------------------------------------------------

# Este documento lo proyecta un preventa delante del cliente. Hablar de escandallo,
# margen o RALF es correcto, son conceptos de Comexi. Lo que no puede salir es la
# cocina: nombres de API, clases, ficheros del repositorio o comandos de despliegue.
# La tentacion es real porque el material de origen esta lleno de ellos.
BUILD_DETAIL = [
    "__c",
    "__r",
    ".cls",
    ".trigger",
    "cumulusci",
    "sfdx",
    "unpackaged",
    "queueable",
    "flexipage",
    "permissionset",
    "metadata api",
    "soql",
    "invocable",
    "createorderfromquote",
    "expressionset",
    "documenttemplate",
    "product2",
    "quotelineitem",
]


def assert_no_build_detail(doc) -> None:
    """Falla si se ha colado un nombre de API o un detalle de construcción."""
    text = " ".join(
        node.text for node in doc.element.body.iter(qn("w:t")) if node.text
    ).lower()
    found = sorted({term for term in BUILD_DETAIL if term in text})
    if found:
        raise AssertionError(
            "El documento se proyecta ante el cliente y contiene detalle de "
            "construcción: " + ", ".join(found)
        )


def build(output: Path) -> None:
    reset_sections()
    doc = Document()
    configure(doc)
    build_header_footer(
        doc.sections[0],
        title=f"Escenarios de demo · Comexi · {SESSION_DATE}",
        # Valor cacheado del campo NUMPAGES: es lo que se lee hasta que Word
        # recalcula los campos al abrir o imprimir. Son 18 paginas medidas, una por
        # salto de pagina, con la mas cargada en 16 de los 23 cm utiles.
        pages="18",
    )

    page_cover(doc)
    page_today(doc)
    page_pains(doc)
    page_priorities(doc)
    page_matrix(doc)
    page_blocks(doc)
    page_coverage(doc)
    page_scope(doc)
    page_next(doc)
    page_annex(doc)

    assert_no_build_detail(doc)
    output.parent.mkdir(parents=True, exist_ok=True)
    doc.save(output)
    print(f"Escrito {output}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Ruta de salida (por defecto {DEFAULT_OUTPUT})",
    )
    args = parser.parse_args()
    build(args.output)


if __name__ == "__main__":
    main()
