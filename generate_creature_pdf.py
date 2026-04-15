#!/usr/bin/env python3
"""Generate a PDF of all Siegelings creatures sorted by class."""

from reportlab.lib.pagesizes import LETTER
from reportlab.lib import colors
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

OUTPUT = "SiegelingsCreaturesByClass.pdf"

# Creature data extracted from CreatureData.lua
creatures = [
    # Fire
    {"name": "Firsky", "element": "Fire", "class": "Mage", "rarity": "Common"},
    {"name": "Pylook", "element": "Fire", "class": "Assassin", "rarity": "Common"},
    {"name": "Sundile", "element": "Fire", "class": "Guardian", "rarity": "Common"},
    {"name": "Draco", "element": "Fire", "class": "Bruiser", "rarity": "Common"},
    {"name": "Emberfox", "element": "Fire", "class": "Support", "rarity": "Common"},
    {"name": "Emberpup", "element": "Fire", "class": "Bruiser", "rarity": "Uncommon"},
    {"name": "Raydile", "element": "Fire", "class": "Guardian", "rarity": "Uncommon"},
    {"name": "Hotty", "element": "Fire", "class": "Support", "rarity": "Uncommon"},
    {"name": "Emberfin", "element": "Fire", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Dracoil", "element": "Fire", "class": "Assassin", "rarity": "Rare"},
    {"name": "Cindergil", "element": "Fire", "class": "Support", "rarity": "Rare"},
    {"name": "Hotdog", "element": "Fire", "class": "Bruiser", "rarity": "Rare"},
    {"name": "Pyleer", "element": "Fire", "class": "Mage", "rarity": "Epic"},
    {"name": "Solgator", "element": "Fire", "class": "Guardian", "rarity": "Epic"},
    {"name": "Pylord", "element": "Fire", "class": "Bruiser", "rarity": "Legendary"},
    # Ice
    {"name": "Fawny", "element": "Ice", "class": "Bruiser", "rarity": "Common"},
    {"name": "Frostfly", "element": "Ice", "class": "Assassin", "rarity": "Common"},
    {"name": "Ice-Wee", "element": "Ice", "class": "Assassin", "rarity": "Common"},
    {"name": "Falcool", "element": "Ice", "class": "Support", "rarity": "Common"},
    {"name": "Cozycub", "element": "Ice", "class": "Mage", "rarity": "Common"},
    {"name": "Frosty", "element": "Ice", "class": "Mage", "rarity": "Uncommon"},
    {"name": "Chilldoe", "element": "Ice", "class": "Bruiser", "rarity": "Uncommon"},
    {"name": "Ice-Cue-Wee", "element": "Ice", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Falcoat", "element": "Ice", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Peatbeak", "element": "Ice", "class": "Guardian", "rarity": "Rare"},
    {"name": "Lumina", "element": "Ice", "class": "Mage", "rarity": "Rare"},
    {"name": "Frostag", "element": "Ice", "class": "Assassin", "rarity": "Epic"},
    {"name": "Glaciemperor", "element": "Ice", "class": "Mage", "rarity": "Legendary"},
    # Wind
    {"name": "Breezee", "element": "Wind", "class": "Assassin", "rarity": "Common"},
    {"name": "Pursula", "element": "Wind", "class": "Bruiser", "rarity": "Common"},
    {"name": "Cloudpuff", "element": "Wind", "class": "Guardian", "rarity": "Common"},
    {"name": "Lofty", "element": "Wind", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Gagglestand", "element": "Wind", "class": "Support", "rarity": "Uncommon"},
    {"name": "Purseus", "element": "Wind", "class": "Mage", "rarity": "Uncommon"},
    {"name": "Cloudwisp", "element": "Wind", "class": "Bruiser", "rarity": "Uncommon"},
    {"name": "Hurricrane", "element": "Wind", "class": "Mage", "rarity": "Rare"},
    {"name": "Cloudsprite", "element": "Wind", "class": "Mage", "rarity": "Rare"},
    {"name": "Shellshock", "element": "Wind", "class": "Assassin", "rarity": "Rare"},
    {"name": "Pursephone", "element": "Wind", "class": "Assassin", "rarity": "Rare"},
    {"name": "Skydon", "element": "Wind", "class": "Support", "rarity": "Epic"},
    {"name": "Strikehawk", "element": "Wind", "class": "Bruiser", "rarity": "Epic"},
    {"name": "Aerovane", "element": "Wind", "class": "Assassin", "rarity": "Legendary"},
    # Earth
    {"name": "Cacty", "element": "Earth", "class": "Bruiser", "rarity": "Common"},
    {"name": "Applehead", "element": "Earth", "class": "Guardian", "rarity": "Common"},
    {"name": "Sleaf", "element": "Earth", "class": "Assassin", "rarity": "Common"},
    {"name": "Squire Bud", "element": "Earth", "class": "Assassin", "rarity": "Common"},
    {"name": "Pylme", "element": "Earth", "class": "Mage", "rarity": "Common"},
    {"name": "Jacked'ty", "element": "Earth", "class": "Bruiser", "rarity": "Uncommon"},
    {"name": "Mossy", "element": "Earth", "class": "Bruiser", "rarity": "Uncommon"},
    {"name": "Flora Knight", "element": "Earth", "class": "Mage", "rarity": "Uncommon"},
    {"name": "Bonoblade", "element": "Earth", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Generoot", "element": "Earth", "class": "Bruiser", "rarity": "Rare"},
    {"name": "Guerilla", "element": "Earth", "class": "Bruiser", "rarity": "Rare"},
    {"name": "Sleafwyrm", "element": "Earth", "class": "Assassin", "rarity": "Rare"},
    {"name": "CactyJackedty", "element": "Earth", "class": "Bruiser", "rarity": "Epic"},
    {"name": "Dracosleaf", "element": "Earth", "class": "Bruiser", "rarity": "Epic"},
    {"name": "Gymstone", "element": "Earth", "class": "Guardian", "rarity": "Legendary"},
    # Shadow
    {"name": "Echo", "element": "Shadow", "class": "Assassin", "rarity": "Common"},
    {"name": "Echowing", "element": "Shadow", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Echolustrious", "element": "Shadow", "class": "Assassin", "rarity": "Rare"},
    {"name": "Umbralwyrm", "element": "Shadow", "class": "Mage", "rarity": "Epic"},
    {"name": "Voidmaw", "element": "Shadow", "class": "Mage", "rarity": "Legendary"},
    # Lightning
    {"name": "Monkwatt", "element": "Lightning", "class": "Mage", "rarity": "Common"},
    {"name": "Newt", "element": "Lightning", "class": "Support", "rarity": "Common"},
    {"name": "Staticap", "element": "Lightning", "class": "Bruiser", "rarity": "Common"},
    {"name": "Blinky", "element": "Lightning", "class": "Guardian", "rarity": "Common"},
    {"name": "Simicircuit", "element": "Lightning", "class": "Support", "rarity": "Uncommon"},
    {"name": "Joltram", "element": "Lightning", "class": "Bruiser", "rarity": "Uncommon"},
    {"name": "Kilokong", "element": "Lightning", "class": "Bruiser", "rarity": "Rare"},
    {"name": "New Ton", "element": "Lightning", "class": "Guardian", "rarity": "Rare"},
    {"name": "Bleetsrike", "element": "Lightning", "class": "Bruiser", "rarity": "Rare"},
    {"name": "Stormclaw", "element": "Lightning", "class": "Bruiser", "rarity": "Epic"},
    {"name": "Thunderlord", "element": "Lightning", "class": "Mage", "rarity": "Legendary"},
    # Water
    {"name": "Spoutyl", "element": "Water", "class": "Assassin", "rarity": "Common"},
    {"name": "Shellpack", "element": "Water", "class": "Support", "rarity": "Common"},
    {"name": "Jawby", "element": "Water", "class": "Guardian", "rarity": "Common"},
    {"name": "Ceeponee", "element": "Water", "class": "Bruiser", "rarity": "Common"},
    {"name": "Droxyl", "element": "Water", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Clawkid", "element": "Water", "class": "Guardian", "rarity": "Uncommon"},
    {"name": "Torqlander", "element": "Water", "class": "Mage", "rarity": "Uncommon"},
    {"name": "Ceehorcee", "element": "Water", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Hydroxyl", "element": "Water", "class": "Assassin", "rarity": "Rare"},
    {"name": "Shellnaut", "element": "Water", "class": "Guardian", "rarity": "Rare"},
    {"name": "Jawbite", "element": "Water", "class": "Support", "rarity": "Rare"},
    {"name": "Claw Queen", "element": "Water", "class": "Mage", "rarity": "Epic"},
    {"name": "Ceesteed", "element": "Ice", "class": "Guardian", "rarity": "Epic"},
    {"name": "Conchious", "element": "Water", "class": "Mage", "rarity": "Legendary"},
    # Light
    {"name": "Light Siegling", "element": "Light", "class": "Support", "rarity": "Common"},
    {"name": "Light Siegling (Daybreak)", "element": "Light", "class": "Support", "rarity": "Uncommon"},
    {"name": "Light Siegling (Solbanner)", "element": "Light", "class": "Guardian", "rarity": "Rare"},
    # Psychic
    {"name": "Mentaroo", "element": "Psychic", "class": "Mage", "rarity": "Common"},
    {"name": "Luvy", "element": "Psychic", "class": "Support", "rarity": "Common"},
    {"name": "Papap", "element": "Psychic", "class": "Assassin", "rarity": "Common"},
    {"name": "Ragguette", "element": "Psychic", "class": "Support", "rarity": "Common"},
    {"name": "Luvysore", "element": "Psychic", "class": "Support", "rarity": "Uncommon"},
    {"name": "Mentarak", "element": "Psychic", "class": "Mage", "rarity": "Rare"},
    {"name": "Luvy Duvysore", "element": "Psychic", "class": "Mage", "rarity": "Epic"},
    {"name": "Psychic Siegling L1", "element": "Psychic", "class": "Mage", "rarity": "Legendary"},
    # Metal
    {"name": "Bearby", "element": "Metal", "class": "Guardian", "rarity": "Common"},
    {"name": "Bearnade", "element": "Metal", "class": "Guardian", "rarity": "Uncommon"},
    {"name": "Bearzooka", "element": "Metal", "class": "Guardian", "rarity": "Rare"},
    {"name": "Metal Siegling E1", "element": "Metal", "class": "Guardian", "rarity": "Epic"},
    {"name": "Metal Siegling L1", "element": "Metal", "class": "Guardian", "rarity": "Legendary"},
    # Poison
    {"name": "Poison Siegling", "element": "Poison", "class": "Assassin", "rarity": "Common"},
    {"name": "Poison Siegling (Venomidge)", "element": "Poison", "class": "Assassin", "rarity": "Uncommon"},
    {"name": "Poison Siegling (Venomapex)", "element": "Poison", "class": "Assassin", "rarity": "Rare"},
    # Undead
    {"name": "Spooky Weed", "element": "Undead", "class": "Bruiser", "rarity": "Common"},
    {"name": "Living Wood", "element": "Undead", "class": "Mage", "rarity": "Uncommon"},
    {"name": "Golor", "element": "Undead", "class": "Guardian", "rarity": "Rare"},
    {"name": "Sheenx", "element": "Undead", "class": "Guardian", "rarity": "Epic"},
]

RARITY_ORDER = {"Common": 0, "Uncommon": 1, "Rare": 2, "Epic": 3, "Legendary": 4}
CLASS_ORDER = ["Assassin", "Bruiser", "Guardian", "Mage", "Support"]

# Colors
CLASS_COLORS = {
    "Assassin": colors.HexColor("#C83CC8"),
    "Bruiser": colors.HexColor("#DC503C"),
    "Guardian": colors.HexColor("#50B4DC"),
    "Mage": colors.HexColor("#6478FF"),
    "Support": colors.HexColor("#64DC78"),
}
RARITY_COLORS = {
    "Common": colors.HexColor("#B4B4B4"),
    "Uncommon": colors.HexColor("#4BC84B"),
    "Rare": colors.HexColor("#3C82FF"),
    "Epic": colors.HexColor("#B450FF"),
    "Legendary": colors.HexColor("#FFB800"),
}
ELEMENT_COLORS = {
    "Fire": colors.HexColor("#FF501E"),
    "Ice": colors.HexColor("#64C8FF"),
    "Wind": colors.HexColor("#96FFB4"),
    "Earth": colors.HexColor("#B48C50"),
    "Shadow": colors.HexColor("#7832B4"),
    "Light": colors.HexColor("#FFFAC8"),
    "Lightning": colors.HexColor("#FFE63C"),
    "Water": colors.HexColor("#3296FF"),
    "Psychic": colors.HexColor("#C896FF"),
    "Metal": colors.HexColor("#A0AAB4"),
    "Poison": colors.HexColor("#78DC50"),
    "Undead": colors.HexColor("#8C78A0"),
}

def lighter(c, factor=0.3):
    """Return a lighter version of a color for table cell backgrounds."""
    return colors.Color(
        c.red + (1 - c.red) * (1 - factor),
        c.green + (1 - c.green) * (1 - factor),
        c.blue + (1 - c.blue) * (1 - factor),
    )


def build_pdf():
    doc = SimpleDocTemplate(OUTPUT, pagesize=LETTER,
                            topMargin=0.5*inch, bottomMargin=0.5*inch,
                            leftMargin=0.6*inch, rightMargin=0.6*inch)
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle("Title2", parent=styles["Title"], fontSize=22, spaceAfter=6)
    subtitle_style = ParagraphStyle("Sub", parent=styles["Normal"], fontSize=10,
                                     textColor=colors.gray, spaceAfter=14)
    class_header_style = ParagraphStyle("ClassH", parent=styles["Heading2"], fontSize=16,
                                         spaceAfter=4, spaceBefore=14)

    story = []
    story.append(Paragraph("Siegelings - All Creatures by Class", title_style))
    story.append(Paragraph(f"Total: {len(creatures)} creatures across {len(CLASS_ORDER)} classes", subtitle_style))

    # Group by class
    by_class = {c: [] for c in CLASS_ORDER}
    for cr in creatures:
        cls = cr["class"]
        # Normalize case
        cls_title = cls.capitalize() if cls[0].islower() else cls
        if cls_title in by_class:
            by_class[cls_title].append(cr)

    for cls in CLASS_ORDER:
        members = sorted(by_class[cls], key=lambda x: (RARITY_ORDER.get(x["rarity"], 0), x["element"], x["name"]))
        cc = CLASS_COLORS[cls]

        story.append(Paragraph(f'<font color="#{cc.hexval()[2:]}">{cls}</font>  ({len(members)} creatures)', class_header_style))

        header = ["#", "Name", "Element", "Rarity"]
        data = [header]
        for i, cr in enumerate(members, 1):
            data.append([str(i), cr["name"], cr["element"], cr["rarity"]])

        col_widths = [0.4*inch, 2.8*inch, 1.4*inch, 1.2*inch]
        t = Table(data, colWidths=col_widths, repeatRows=1)

        style_cmds = [
            ("BACKGROUND", (0, 0), (-1, 0), cc),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("FONTSIZE", (0, 0), (-1, 0), 10),
            ("FONTSIZE", (0, 1), (-1, -1), 9),
            ("FONTNAME", (0, 1), (-1, -1), "Helvetica"),
            ("ALIGN", (0, 0), (0, -1), "CENTER"),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.Color(0.8, 0.8, 0.8)),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.Color(0.96, 0.96, 0.96)]),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]

        # Color-code rarity text
        for row_idx in range(1, len(data)):
            rarity = data[row_idx][3]
            rc = RARITY_COLORS.get(rarity, colors.black)
            style_cmds.append(("TEXTCOLOR", (3, row_idx), (3, row_idx), rc))
            style_cmds.append(("FONTNAME", (3, row_idx), (3, row_idx), "Helvetica-Bold"))
            # Color-code element text
            elem = data[row_idx][2]
            ec = ELEMENT_COLORS.get(elem, colors.black)
            style_cmds.append(("TEXTCOLOR", (2, row_idx), (2, row_idx), ec))
            style_cmds.append(("FONTNAME", (2, row_idx), (2, row_idx), "Helvetica-Bold"))

        t.setStyle(TableStyle(style_cmds))
        story.append(t)
        story.append(Spacer(1, 12))

    doc.build(story)
    print(f"PDF generated: {OUTPUT}")


if __name__ == "__main__":
    build_pdf()
