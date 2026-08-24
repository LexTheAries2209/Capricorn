#!/usr/bin/env python3
"""Build the Solidigm/SN640 catalog-review PDF from Capricorn's JSON catalog.

The report is intentionally an incremental review. It shows the Solidigm and
SN640 records relevant to this update, with new records in green and changed
recognition patterns in yellow. It does not manufacture unverified aliases
from the source spreadsheet.
"""

from __future__ import annotations

import json
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A3, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "Capricorn/Resources/ExternalDriveModels.json"
OUTPUT_PATH = ROOT / "output/pdf/capricorn-solidigm-model-catalog-review.pdf"
CHINESE_FONT_PATH = Path("/Library/Fonts/DroidSansFallback.ttf")
CHINESE_FONT_NAME = "DroidSansFallback"

# The status is deliberately keyed by the persistent record id rather than a
# presentation string, so a marketing-name edit cannot accidentally lose its
# audit color in future regenerated reports.
NEW_RECORD_IDS = {
    "intel-solidigm-d5-p4320",
    "intel-solidigm-d5-p4326",
    "intel-solidigm-d5-p4420",
    "intel-solidigm-d7-p4510",
    "intel-solidigm-d7-p4511",
    "intel-solidigm-d7-p4610",
    "solidigm-d7-p5810",
    "solidigm-d5-p5430",
    "solidigm-d5-p5336",
    "solidigm-d7-ps1010",
    "solidigm-d7-ps1030",
    "wd-ultrastar-sn640",
}

MODIFIED_RECORD_IDS = {
    "solidigm-d5-p5316",
    "solidigm-d7-p5520",
    "solidigm-d7-p5620",
}

OFFICIAL_SOURCE_NOTES = [
    [
        "Intel / Solidigm enterprise families",
        "Intel PCN 117969-00 and Solidigm product documentation",
        "D5-P4320, D5-P4326, D5-P4420, D7-P4510, D7-P4511, D7-P4610",
    ],
    [
        "D5-P5430 / D5-P5336",
        "Solidigm D5-P5430 documentation; PCN0000040342-00 (2025)",
        "Includes the 122.88 TB D5-P5336 ordering code SBFPF2BV0P12001",
    ],
    [
        "D7-PS1010 / D7-PS1030",
        "Solidigm D7-PS1010/PS1030 product brief (2025)",
        "Current PCIe 5.0 data-center series added this revision",
    ],
    [
        "WD Ultrastar DC SN640",
        "Western Digital Ultrastar DC SN640 data sheet",
        "SN640 is a WD/SanDisk product, retained here because it was an explicit coverage gap",
    ],
]


def status_for(record_id: str) -> str:
    if record_id in NEW_RECORD_IDS:
        return "新增"
    if record_id in MODIFIED_RECORD_IDS:
        return "修改"
    return "既有"


def paragraph(text: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"), style)


def display_examples(record: dict) -> str:
    examples = record.get("examples", [])
    if not examples:
        return "-"
    return "<br/>".join(example["reportedModel"] for example in examples)


def display_capacity_labels(record: dict) -> str:
    labels = record.get("capacityLabels", {})
    if labels:
        return " · ".join(f"{token} -> {label}" for token, label in labels.items())
    examples = record.get("examples", [])
    values = [example.get("capacityToken", "") for example in examples if example.get("capacityToken")]
    return " · ".join(values) or "型号本身不含容量"


def catalog_rows(records: list[dict], body: ParagraphStyle) -> list[list[Paragraph]]:
    rows = []
    for record in records:
        rows.append(
            [
                paragraph(status_for(record["id"]), body),
                paragraph(record["manufacturer"], body),
                paragraph(record["family"], body),
                paragraph(record["mediaKind"], body),
                paragraph(" / ".join(record.get("interfaces", [])), body),
                paragraph(display_examples(record), body),
                paragraph(display_capacity_labels(record), body),
            ]
        )
    return rows


def make_catalog_table(records: list[dict], styles: dict[str, ParagraphStyle]) -> Table:
    header = ["变更", "品牌", "商品名 / 系列", "介质", "接口", "典型上报型号", "容量转换"]
    rows: list[list[object]] = [[paragraph(value, styles["tableHeader"]) for value in header]]
    rows.extend(catalog_rows(records, styles["tableBody"]))
    table = Table(
        rows,
        colWidths=[16 * mm, 30 * mm, 43 * mm, 20 * mm, 28 * mm, 102 * mm, 46 * mm],
        repeatRows=1,
        hAlign="LEFT",
    )
    table_style = [
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#20372A")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#A8B5AA")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 2.5 * mm),
        ("RIGHTPADDING", (0, 0), (-1, -1), 2.5 * mm),
        ("TOPPADDING", (0, 0), (-1, -1), 2.2 * mm),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.2 * mm),
    ]
    for index, record in enumerate(records, start=1):
        row_color = {
            "新增": colors.HexColor("#DDF3E3"),
            "修改": colors.HexColor("#FFF2C2"),
            "既有": colors.white,
        }[status_for(record["id"])]
        table_style.append(("BACKGROUND", (0, index), (-1, index), row_color))
    table.setStyle(TableStyle(table_style))
    return table


def footer(canvas, document) -> None:
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.HexColor("#5A625C"))
    canvas.drawString(18 * mm, 11 * mm, "Capricorn - Solidigm / SN640 model catalog review")
    canvas.drawRightString(402 * mm, 11 * mm, f"{document.page}")
    canvas.restoreState()


def main() -> None:
    if not CHINESE_FONT_PATH.exists():
        raise RuntimeError(f"Required Chinese font is unavailable: {CHINESE_FONT_PATH}")
    pdfmetrics.registerFont(TTFont(CHINESE_FONT_NAME, str(CHINESE_FONT_PATH)))
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    record_map = {record["id"]: record for record in catalog["records"]}
    missing_ids = (NEW_RECORD_IDS | MODIFIED_RECORD_IDS) - record_map.keys()
    if missing_ids:
        raise RuntimeError(f"Catalog records missing from review definition: {sorted(missing_ids)}")

    relevant = [
        record
        for record in catalog["records"]
        if record["manufacturer"] in {"Intel", "Intel/Solidigm", "Solidigm", "WD"}
        and (
            record["manufacturer"] != "WD"
            or record["id"] == "wd-ultrastar-sn640"
        )
    ]
    new_records = [record for record in relevant if status_for(record["id"]) == "新增"]
    modified_records = [record for record in relevant if status_for(record["id"]) == "修改"]
    existing_records = [record for record in relevant if status_for(record["id"]) == "既有"]

    sheet = getSampleStyleSheet()
    styles = {
        "title": ParagraphStyle(
            "reviewTitle", parent=sheet["Title"], fontName=CHINESE_FONT_NAME, fontSize=26, leading=34, textColor=colors.HexColor("#17251C")
        ),
        "subtitle": ParagraphStyle(
            "reviewSubtitle", parent=sheet["BodyText"], fontName=CHINESE_FONT_NAME, fontSize=11, leading=17, textColor=colors.HexColor("#425248")
        ),
        "heading": ParagraphStyle(
            "reviewHeading", parent=sheet["Heading2"], fontName=CHINESE_FONT_NAME, fontSize=16, leading=22, textColor=colors.HexColor("#17251C"), spaceBefore=4 * mm, spaceAfter=3 * mm
        ),
        "body": ParagraphStyle(
            "reviewBody", parent=sheet["BodyText"], fontName=CHINESE_FONT_NAME, fontSize=10, leading=15, textColor=colors.HexColor("#1D2821")
        ),
        "tableHeader": ParagraphStyle(
            "reviewTableHeader", parent=sheet["BodyText"], fontName=CHINESE_FONT_NAME, fontSize=8.5, leading=11, textColor=colors.white, alignment=TA_CENTER
        ),
        "tableBody": ParagraphStyle(
            "reviewTableBody", parent=sheet["BodyText"], fontName=CHINESE_FONT_NAME, fontSize=8, leading=11, textColor=colors.HexColor("#17251C"), alignment=TA_LEFT
        ),
        "note": ParagraphStyle(
            "reviewNote", parent=sheet["BodyText"], fontName=CHINESE_FONT_NAME, fontSize=8.5, leading=13, textColor=colors.HexColor("#3B4940")
        ),
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    document = SimpleDocTemplate(
        str(OUTPUT_PATH),
        pagesize=landscape(A3),
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=17 * mm,
        bottomMargin=18 * mm,
        title="Capricorn Solidigm / SN640 model catalog review",
        author="Capricorn",
    )
    story = [
        paragraph("Capricorn 商品名 - 型号目录核对表", styles["title"]),
        Spacer(1, 2 * mm),
        paragraph("Solidigm / Intel 企业盘与 WD Ultrastar DC SN640 增量核对 | 2026-08-24", styles["subtitle"]),
        Spacer(1, 6 * mm),
    ]
    summary_data = [
        [paragraph("本次新增", styles["tableHeader"]), paragraph("本次修改", styles["tableHeader"]), paragraph("现有保留", styles["tableHeader"])],
        [paragraph(str(len(new_records)), styles["body"]), paragraph(str(len(modified_records)), styles["body"]), paragraph(str(len(existing_records)), styles["body"])],
    ]
    summary = Table(summary_data, colWidths=[47 * mm, 47 * mm, 47 * mm])
    summary.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, 0), colors.HexColor("#61A873")),
                ("BACKGROUND", (1, 0), (1, 0), colors.HexColor("#D6A21B")),
                ("BACKGROUND", (2, 0), (2, 0), colors.HexColor("#607566")),
                ("BACKGROUND", (0, 1), (0, 1), colors.HexColor("#DDF3E3")),
                ("BACKGROUND", (1, 1), (1, 1), colors.HexColor("#FFF2C2")),
                ("BACKGROUND", (2, 1), (2, 1), colors.HexColor("#F4F7F4")),
                ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#A8B5AA")),
                ("INNERGRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#A8B5AA")),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 3 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3 * mm),
            ]
        )
    )
    story.extend(
        [
            summary,
            Spacer(1, 6 * mm),
            paragraph("标注规则", styles["heading"]),
            paragraph("绿色表示本版本新加入运行时匹配的型号记录；黄色表示已有记录仅扩展了已验证的 U.2/E1.L 料号覆盖。未着色记录保留原有映射，列出是为了方便检查本次 Solidigm 覆盖范围。", styles["body"]),
            Spacer(1, 4 * mm),
            paragraph("附件核对结论", styles["heading"]),
            paragraph("附件中的 D5-5530 与 D5-5536 未在 Solidigm 官方产品资料中找到对应系列，因此不会被作为别名写入匹配库。已覆盖的正确 D5-P5336 支持 7.68 TB 至 122.88 TB 的订单型号；这避免把错误上报型号静默映射为真实商品名。", styles["body"]),
            Spacer(1, 4 * mm),
            paragraph("范围说明", styles["heading"]),
            paragraph("本表以商品名数据库的上报型号规则为准，不取代硬盘固件、容量或接口的真实性检测。SN640 归属 WD/SanDisk，因用户指出覆盖缺口而与 Solidigm 增量一起核对。", styles["body"]),
            PageBreak(),
            paragraph("本次新增的型号映射", styles["heading"]),
            paragraph("以下行均为绿色新增。典型上报型号来自对应的官方订购料号或产品资料，避免仅凭营销系列前缀匹配。", styles["subtitle"]),
            Spacer(1, 3 * mm),
            make_catalog_table(new_records, styles),
            PageBreak(),
            paragraph("本次修改与既有覆盖", styles["heading"]),
            paragraph("黄色行表示没有改变商品名，只增加了官方可验证的 E1.L / U.2 料号形式；其余为现有 Solidigm / Intel 记录。", styles["subtitle"]),
            Spacer(1, 3 * mm),
            make_catalog_table(modified_records + existing_records, styles),
            PageBreak(),
            paragraph("来源与审查说明", styles["heading"]),
            paragraph("资料均以厂商的产品页面、产品简报或产品变更通知（PCN）为准。PDF 中的超链接未嵌入；运行时目录保留每条记录的 sourceURL。", styles["body"]),
            Spacer(1, 4 * mm),
        ]
    )
    source_header = ["覆盖项", "官方资料", "核对要点"]
    source_data = [[paragraph(value, styles["tableHeader"]) for value in source_header]]
    source_data.extend([[paragraph(value, styles["tableBody"]) for value in row] for row in OFFICIAL_SOURCE_NOTES])
    sources = Table(source_data, colWidths=[54 * mm, 112 * mm, 166 * mm], repeatRows=1)
    sources.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#20372A")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#A8B5AA")),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 3 * mm),
                ("RIGHTPADDING", (0, 0), (-1, -1), 3 * mm),
                ("TOPPADDING", (0, 0), (-1, -1), 2.8 * mm),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2.8 * mm),
            ]
        )
    )
    story.extend(
        [
            sources,
            Spacer(1, 6 * mm),
            paragraph("验证状态", styles["heading"]),
            paragraph("目录 JSON 已通过完整示例匹配测试、跨厂商 U.2/U.3 覆盖测试，以及本次新增 Solidigm 和 SN640 的定向断言。对于无法在官方资料中证实的附件行，本版本采取不写入而非猜测映射的策略。", styles["body"]),
        ]
    )
    document.build(story, onFirstPage=footer, onLaterPages=footer)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    main()
