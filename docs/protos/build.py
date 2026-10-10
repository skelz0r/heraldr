#!/usr/bin/env python3
"""Generates the UI direction mockups. Edit this file, then run `python3 build.py`.

Every HTML file is overwritten on each run: never edit them by hand.
"""

import pathlib
import random
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).parent
LOGO_SOURCE = ROOT.parent / "branding" / "logo"
DEFAULT_LOGO = "1-eventail"
DEFAULT_NAME = "Cooee"

TITLE = "Compagnon herdr : quatre directions pour l'écran principal"
INTRO = """
    <p>Quatre façons de dessiner l'écran principal de l'app iOS : la liste des workspaces herdr, la cible des envois et les trois boutons <b>Écrire · Dicter · Coller</b>. Elles ne diffèrent que sur <b>la disposition de cet écran</b> : comment on lit les états, comment on choisit la cible, quelle place prend la voix.</p>
    <p>Tout le reste est invariant et strictement identique d'une direction à l'autre : appairage, dictée, nettoyage Foundation Models, aperçu, file d'attente, erreurs. Chaque direction se déroule de l'appairage jusqu'au retour sur l'accueil après un envoi mis en file, en clair et en sombre.</p>
"""
FOOTER = "Maquettes statiques, Liquid Glass émulé en CSS. Le Mac et les adresses sont fictifs, seuls les noms des workspaces sont réels."

LABELS = {
    "annotations": "Annotations",
    "position": "écran {num} sur {total}",
    "off_path": "écran hors parcours",
    "back_to_index": "Toutes les directions",
    "screens": "{n} écrans",
    "walk": "Dérouler le parcours",
    "scenario": "Principe.",
    "requires": "Ce que ça demande.",
    "matrix": "Synthèse",
    "criterion": "Critère",
    "screens_row": "Écrans",
    "reading": "Lire les maquettes",
    "notes_legend": "Les commentaires sont en marge, numérotés, et renvoient à des repères dans l'écran : {info} un constat, {good} un point fort, {weak} une faiblesse.",
    "not_shown": "Ce que les maquettes ne montrent pas",
}

MAC = "MacBook-Exemple"
MAC_USER = "demo"
LAN_ADDR = "192.168.1.20"
TAILSCALE_ADDR = "100.64.0.20"
FINGERPRINT = "SHA256:Exemple9f3cA1b2…"

WORKSPACES = [
    ("~", "idle", False),
    ("local_events", "working", True),
    ("apistration", "done", False),
    ("acme_app", "working", False),
    ("freebox-delta-vm", "idle", False),
    ("herdr-plugin-space-agents", "blocked", False),
    ("Herdr ios companion", "done", False),
]
TARGET = "acme_app"
CARD_COLORS = {
    "~": "#55555f",
    "local_events": "#3a7d6b",
    "apistration": "#6a5acd",
    "acme_app": "#c0436b",
    "freebox-delta-vm": "#2f6fa3",
    "herdr-plugin-space-agents": "#8a6a2f",
    "Herdr ios companion": "#7a4a9a",
}
STATUS_FR = {"idle": "inactif", "working": "travaille", "blocked": "bloqué", "done": "terminé"}

RAW_TEXT = ("Euh, ajoute un, un export CSV des… des dossiers validés dans le back-office, euh, "
            "filtrable par date de validation")
CLEAN_TEXT = "Ajoute un export CSV des dossiers validés dans le back-office, filtrable par date de validation."
PASTE_TEXT = ("Le webhook de paiement renvoie une 500 quand le client n'a pas d'adresse : "
              "NoMethodError: undefined method `country' for nil (PaymentsController#webhook)")

OPTIONS = {
    "direction-a": {
        "label": "Direction A",
        "title": "Liste vitrée et dock flottant",
        "where": "proche du natif",
        "scenario": "Une liste de rangées en verre, la cible remplie de violet avec une coche. Un dock flottant en bas porte Écrire, Dicter et Coller ; la cible est rappelée juste au-dessus.",
        "requires": "Le moins de sur-mesure : List SwiftUI, glassEffect, un dock. Le risque est de ressembler à une app iOS standard.",
        "reco": False,
    },
    "direction-b": {
        "label": "Direction B",
        "title": "Micro géant et carrousel",
        "where": "la voix d'abord",
        "scenario": "Le micro occupe le centre de l'écran. Les workspaces sont des pastilles dans un carrousel horizontal en haut, la cible s'affiche en très gros sous le carrousel.",
        "requires": "Un orbe et un carrousel sur mesure. Accepter de ne plus voir l'état de tous les workspaces d'un coup.",
        "reco": False,
    },
    "direction-c": {
        "label": "Direction C",
        "title": "Pile de cartes",
        "where": "façon Cartes",
        "scenario": "Chaque workspace est une carte colorée, empilée comme dans Cartes (Wallet). La carte cible s'ouvre sur place ; trois tuiles en bas, la voix plus haute.",
        "requires": "Un composant de pile entièrement sur mesure, une palette d'identité par workspace, l'accessibilité à refaire.",
        "reco": False,
    },
    "direction-d": {
        "label": "Direction D",
        "title": "Une main, tout en bas",
        "where": "recommandée",
        "scenario": "La moitié haute se lit (la cible en 40 pt, son état), la moitié basse se touche : grille de workspaces à deux colonnes, puis une barre où le bouton voix fait saillie comme un déclencheur photo.",
        "requires": "Une grille et une barre sur mesure, simples. Les noms longs passent sur deux lignes.",
        "reco": True,
    },
}

CRITERIA = [
    ("États de tous les workspaces visibles", {
        "direction-a": ("good", "Oui, sept lignes"),
        "direction-b": ("weak", "Non, carrousel : trois ou quatre sur sept"),
        "direction-c": ("good", "Oui, en bord de carte"),
        "direction-d": ("good", "Oui, grille à deux colonnes"),
    }),
    ("Force de la sélection", {
        "direction-a": ("good", "Ligne remplie, coche, rappel au-dessus du dock"),
        "direction-b": ("info", "Pastille remplie, nom géant"),
        "direction-c": ("good", "La carte s'ouvre et s'entoure"),
        "direction-d": ("good", "Tuile remplie et nom en 40 pt"),
    }),
    ("Dominance de la voix", {
        "direction-a": ("weak", "92 pt dans un dock, l'œil va à la liste"),
        "direction-b": ("good", "224 pt au centre"),
        "direction-c": ("info", "Tuile plus haute, peu plus grande"),
        "direction-d": ("good", "128 pt en saillie"),
    }),
    ("Une main, en marchant", {
        "direction-a": ("info", "Haut de liste hors du pouce"),
        "direction-b": ("weak", "Balayer le carrousel pour changer de cible"),
        "direction-c": ("weak", "Haut de pile hors du pouce"),
        "direction-d": ("good", "Tout ce qui se touche est en bas"),
    }),
    ("Écart au look natif", {
        "direction-a": ("weak", "Proche d'une List iOS"),
        "direction-b": ("good", "Très marqué"),
        "direction-c": ("good", "Très marqué"),
        "direction-d": ("good", "Marqué"),
    }),
    ("Coût SwiftUI", {
        "direction-a": ("good", "List et glassEffect"),
        "direction-b": ("info", "Carrousel et orbe"),
        "direction-c": ("weak", "Pile sur mesure, VoiceOver à refaire"),
        "direction-d": ("info", "LazyVGrid et barre sur mesure"),
    }),
    ("Passage à quinze workspaces", {
        "direction-a": ("good", "Défilement natif"),
        "direction-b": ("weak", "Carrousel interminable"),
        "direction-c": ("weak", "Pile très haute"),
        "direction-d": ("info", "La grille défile sous la zone de lecture"),
    }),
]

RECOMMENDATION = """
    <div class="reco-box">
      <p><b>Recommandation : direction D.</b> C'est la seule qui coche en même temps les trois principes de la vision : utilisable d'une main en marchant, bouton voix dominant, pas un look natif standard. Elle garde l'état des sept workspaces sous les yeux, ce que B sacrifie.</p>
      <p>Repli : <b>direction A</b> si le coût doit être minimal ; on peut lui emprunter la zone de lecture de D plus tard. B et C sont plus spectaculaires mais perdent sur la lisibilité des états (B) ou le coût et l'accessibilité (C).</p>
    </div>
"""

NOT_SHOWN = [
    "<b>Le vrai Liquid Glass.</b> La réfraction, la lumière qui suit l'inclinaison et la morphose des boutons ne sont qu'approchées en CSS (flou, translucidité, reflets).",
    "<b>Les animations de transition.</b> Seuls le dot bleu, l'onde de dictée et le nettoyage sont animés.",
    "<b>Le pull-to-refresh.</b> Identique dans toutes les directions, sans effet sur la décision.",
    "<b>Ce qui est hors MVP.</b> Réponse aux questions de l'agent, notifications, détail par agent, historique.",
]


KINDS = ("info", "good", "weak")
WALKTHROUGHS = []
WARNINGS = []


def warn(message):
    WARNINGS.append(message)


def m(n, kind="info"):
    suffix = "" if kind == "info" else f" marker--{kind}"
    return f'<span class="marker{suffix}">{n}</span>'


ICONS = {
    "pencil": '<path d="M4 20h4L19 9l-4-4L4 16v4z"/><path d="M14 6l4 4"/>',
    "mic": '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/>',
    "clip": '<rect x="5.5" y="4.5" width="13" height="16" rx="2.5"/><rect x="9" y="2.5" width="6" height="4" rx="1.2"/><path d="M9 11h6M9 15h4"/>',
    "check": '<path d="M5 12.5l4.5 4.5L19 7"/>',
    "chev": '<path d="M6 9l6 6 6-6"/>',
    "up": '<path d="M12 19V5M6 11l6-6 6 6"/>',
    "x": '<path d="M6 6l12 12M18 6L6 18"/>',
    "spark": '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z"/>',
    "clock": '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    "alert": '<path d="M12 3.5L22 20H2z"/><path d="M12 10v4.5M12 17.5v.2"/>',
    "mac": '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M1.5 19.5h21"/>',
    "arrow": '<path d="M5 12h14M13 6l6 6-6 6"/>',
}


def icon(name, size=24, stroke=2):
    return (f'<svg class="ic" width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
            f'stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round">{ICONS[name]}</svg>')


STATUS_BAR = """<div class="sbar"><span>9:41</span><span class="icons">
<svg width="18" height="12" viewBox="0 0 18 12" fill="currentColor"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
<svg width="16" height="12" viewBox="0 0 16 12" fill="currentColor"><path d="M8 2.2c2.4 0 4.6.9 6.2 2.5l1.2-1.2C13.4 1.5 10.8.5 8 .5S2.6 1.5.6 3.5l1.2 1.2C3.4 3.1 5.6 2.2 8 2.2z"/><path d="M8 5.6c1.5 0 2.8.6 3.8 1.5L13 5.9C11.7 4.7 9.9 3.9 8 3.9s-3.7.8-5 2l1.2 1.2c1-.9 2.3-1.5 3.8-1.5z"/><circle cx="8" cy="10" r="1.8"/></svg>
<svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.5" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="18" height="9" rx="2" fill="currentColor"/><rect x="24.5" y="4.5" width="2" height="4" rx="1" fill="currentColor" opacity=".4"/></svg>
</span></div>"""


def phone(content, theme):
    return f"""<div class="phone t-{theme}"><div class="scr">
<div class="wall"><i class="b1"></i><i class="b2"></i><i class="b3"></i></div>
<div class="island"></div>
{STATUS_BAR}
{content}
<div class="homebar"></div>
</div></div>"""


def dot(status):
    return f'<span class="dot s-{status}"></span>'


def wait_badge():
    return f'<span class="wait">{icon("clock", 12, 2.4)}en attente</span>'


def state(queued):
    return [(label, status, was_queued or label in queued) for label, status, was_queued in WORKSPACES]


def status_of(label):
    return next(status for name, status, _ in WORKSPACES if name == label)


def brand_logo(cls=""):
    return f'<img class="brand-logo {cls}" src="../logos/{DEFAULT_LOGO}.svg" alt="">'


def brand_name():
    return f'<b class="brand-name">{DEFAULT_NAME}</b>'


def mac_pill(mark=""):
    return f'<span class="pill mac g">{brand_logo()}{brand_name()}<span class="brand-sep"></span>{dot("done")}{MAC}{mark}</span>'


def toast_queued(mark=""):
    return f"""<div class="toast g"><span class="ico">{icon("clock", 20, 2.4)}</span>
<div><b>En file pour {TARGET}{mark}</b><span class="sub">L'agent travaille : l'envoi partira dès qu'il aura fini.</span></div></div>"""


# ---------- Direction mains ----------
# Each main(selected, hrefs, queued, toast, marks) returns the content of the home screen.
# hrefs keys: "row:<label>", "voice", "write", "paste". marks keys depend on the direction.


def href(hrefs, key):
    return hrefs.get(key, "#")


def main_a(selected, hrefs, queued=frozenset(), toast=False, marks=None):
    marks = marks or {}
    rows = []
    for label, status, is_queued in state(queued):
        is_sel = label == selected
        cls = "a-row tint" if is_sel else "a-row g"
        extra = wait_badge() if is_queued else ""
        tail = f'<span class="chk">{icon("check", 16, 3)}</span>' if is_sel else f'<span class="st">{STATUS_FR[status]}</span>'
        mark = marks.get(f"row:{label}", "")
        rows.append(f'<a class="{cls}" href="{href(hrefs, "row:" + label)}">{dot(status)}'
                    f'<span class="lbl">{label}</span>{extra}{mark}{tail}</a>')
    return f"""<div class="col">
<div class="a-head">{mac_pill()}<h1>Workspaces{marks.get("list", "")}</h1></div>
<div class="a-list">
{chr(10).join(rows)}
</div>
<div class="a-target pill g">{icon("arrow", 16, 2.4)}Cible : <b>{selected}</b>{marks.get("target", "")}</div>
<div class="a-dock g">
<a class="a-side" href="{href(hrefs, "write")}">{icon("pencil", 26)}Écrire</a>
<a class="a-voice tint" href="{href(hrefs, "voice")}">{icon("mic", 40, 2.2)}{marks.get("voice", "")}</a>
<a class="a-side" href="{href(hrefs, "paste")}">{icon("clip", 26)}Coller</a>
</div>
</div>{toast_queued(marks.get("toast", "")) if toast else ""}"""


def main_b(selected, hrefs, queued=frozenset(), toast=False, marks=None):
    marks = marks or {}
    chips = []
    items = state(queued)
    for label, status, is_queued in items:
        cls = "b-chip tint" if label == selected else "b-chip g"
        extra = wait_badge() if is_queued else ""
        chips.append(f'<a class="{cls}" href="{href(hrefs, "row:" + label)}">{dot(status)}{label}{extra}</a>')
    counts = {s: sum(1 for _, st, _ in items if st == s) for s in ("blocked", "working", "done")}
    summary = (f'<span>{dot("blocked")}{counts["blocked"]} bloqué</span>'
               f'<span>{dot("working")}{counts["working"]} travaillent</span>'
               f'<span>{dot("done")}{counts["done"]} terminés</span>')
    status = status_of(selected)
    target_queued = any(label == selected and q for label, _, q in items)
    return f"""<div class="col">
<div class="b-top">{mac_pill()}</div>
<div class="b-car">{marks.get("carousel", "")}{"".join(chips)}</div>
<div class="b-sum">{summary}{marks.get("summary", "")}</div>
<div class="b-target"><div class="eyebrow">Cible</div><div class="big">{selected}{marks.get("target", "")}</div>
<div class="st">{dot(status)}{STATUS_FR[status]}{" · " + wait_badge() if target_queued else ""}</div></div>
<div class="b-orb-wrap"><a class="b-orb tint" href="{href(hrefs, "voice")}">{icon("mic", 84, 1.8)}{marks.get("voice", "")}</a></div>
<div class="b-hint">Toucher pour dicter</div>
<div class="b-sides">
<a class="b-side g" href="{href(hrefs, "write")}">{icon("pencil", 24)}Écrire{marks.get("sides", "")}</a>
<a class="b-side g" href="{href(hrefs, "paste")}">{icon("clip", 24)}Coller</a>
</div>
</div>{toast_queued(marks.get("toast", "")) if toast else ""}"""


def main_c(selected, hrefs, queued=frozenset(), toast=False, marks=None):
    marks = marks or {}
    cards = []
    for label, status, is_queued in state(queued):
        color = CARD_COLORS[label]
        mark = marks.get(f"row:{label}", "")
        if label == selected:
            cards.append(f"""<a class="c-card sel" style="--c:{color}" href="{href(hrefs, "row:" + label)}">
<div class="row"><span class="cible">Cible</span>{mark}</div>
<div class="big">{label}</div>
<div class="meta">{dot(status)}{STATUS_FR[status]}{wait_badge() if is_queued else ""}</div>
</a>""")
        else:
            extra = wait_badge() if is_queued else ""
            cards.append(f'<a class="c-card" style="--c:{color}" href="{href(hrefs, "row:" + label)}">'
                         f'<span class="lbl">{label}</span>{extra}{mark}{dot(status)}</a>')
    return f"""<div class="col">
<div class="c-top"><h1>Workspaces{marks.get("list", "")}</h1>{mac_pill()}</div>
<div class="c-stack">
{chr(10).join(cards)}
</div>
<div class="c-btns">
<a class="c-tile g" href="{href(hrefs, "write")}">{icon("pencil", 30)}Écrire</a>
<a class="c-tile v tint" href="{href(hrefs, "voice")}">{icon("mic", 48, 2)}Dicter{marks.get("voice", "")}</a>
<a class="c-tile g" href="{href(hrefs, "paste")}">{icon("clip", 30)}Coller</a>
</div>
</div>{toast_queued(marks.get("toast", "")) if toast else ""}"""


def main_d(selected, hrefs, queued=frozenset(), toast=False, marks=None):
    marks = marks or {}
    tiles = []
    items = state(queued)
    for label, status, is_queued in items:
        cls = "d-tile tint" if label == selected else "d-tile g"
        extra = wait_badge() if is_queued else ""
        mark = marks.get(f"row:{label}", "")
        tiles.append(f'<a class="{cls}" href="{href(hrefs, "row:" + label)}">{dot(status)}'
                     f'<span class="lbl"><span>{label}{mark}</span>{extra}</span></a>')
    status = status_of(selected)
    target_queued = any(label == selected and q for label, _, q in items)
    hint = {
        "idle": "prêt : contexte vidé puis envoi",
        "done": "prêt : contexte vidé puis envoi",
        "working": "l'envoi partira après son travail",
        "blocked": "attend une réponse : l'envoi patientera",
    }[status]
    return f"""<div class="col">
<div class="d-read">
<div>{mac_pill()}</div>
<div class="spacer"></div>
<div class="eyebrow">Cible{marks.get("read", "")}</div>
<div class="big">{selected}</div>
<div class="st">{dot(status)}<span>{STATUS_FR[status]} · {hint}</span>{marks.get("status", "")}</div>
{f'<div class="st">{wait_badge()}</div>' if target_queued else ""}
<div class="spacer"></div>
</div>
<div class="d-grid">{marks.get("grid", "")}
{chr(10).join(tiles)}
</div>
<div class="d-bar g">
<a class="d-side" href="{href(hrefs, "write")}">{icon("pencil", 28)}Écrire</a>
<span></span>
<a class="d-side" href="{href(hrefs, "paste")}">{icon("clip", 28)}Coller</a>
<a class="d-voice tint" href="{href(hrefs, "voice")}">{icon("mic", 56, 2)}{marks.get("voice", "")}</a>
</div>
</div>{toast_queued(marks.get("toast", "")) if toast else ""}"""


# ---------- Shared screens ----------


def qr_svg():
    rng = random.Random(7)
    size = 25
    cells = []
    finders = [(0, 0), (0, size - 7), (size - 7, 0)]

    def in_finder(x, y):
        return any(fx <= x < fx + 7 and fy <= y < fy + 7 for fx, fy in finders)

    for y in range(size):
        for x in range(size):
            if in_finder(x, y):
                continue
            if rng.random() < .48:
                cells.append(f'<rect x="{x}" y="{y}" width="1" height="1"/>')
    for fx, fy in finders:
        cells.append(f'<rect x="{fx}" y="{fy}" width="7" height="7"/><rect x="{fx + 1}" y="{fy + 1}" width="5" height="5" fill="#fff"/>'
                     f'<rect x="{fx + 2}" y="{fy + 2}" width="3" height="3"/>')
    return f'<svg viewBox="0 0 {size} {size}" width="160" height="160" shape-rendering="crispEdges">{"".join(cells)}</svg>'


def screen_pairing(w, next_href):
    w.screen("1-appairage.html", title="Appairage", offpath=[
        ("icone.html", "Icône"), ("lancement.html", "Lancement")], body=f"""<div class="pair"></div>
<div class="pair-qr">{qr_svg()}</div>
<div class="pair-frame"><i></i><i></i><i></i><i></i></div>
<div class="pair-hint g"><div class="pair-brand">{brand_logo()}{brand_name()}</div>Sur le Mac, affichez le QR d'appairage :<code>herdr plugin action invoke heeler.pair{m(1, "good")}</code></div>
<div class="pair-sheet g">
<div class="eyebrow">HERDR-PAIR:1 détecté</div>
<h2>{MAC}</h2>
<dl>
<dt>Compte</dt><dd>{MAC_USER}</dd>
<dt>Adresses</dt><dd>{LAN_ADDR} (LAN), {TAILSCALE_ADDR} (Tailscale)</dd>
<dt>Empreinte</dt><dd><code>{FINGERPRINT}</code>{m(2)}</dd>
<dt>Code</dt><dd>expire dans 1:42</dd>
</dl>
<a class="big-btn tint" href="{next_href}">Associer ce Mac{m(3, "weak")}</a>
</div>""", notes=[
        ("good", "Rien de neuf côté Mac",
         "Le QR vient de l'action <code>heeler.pair</code> du plugin Heeler déjà installé, au format <code>HERDR-PAIR:1</code>."),
        ("info", "Empreinte épinglée",
         "L'app retient l'empreinte de la clé hôte, puis essaie l'adresse LAN avant Tailscale."),
        ("weak", "Code valable deux minutes",
         "La clé bootstrap est à usage unique : si l'enrôlement échoue, il faut relancer <code>heeler.pair</code> sur le Mac."),
    ])


def screen_recording(w, next_href):
    bars = "".join(f'<i style="height:{h}px;animation-delay:-{d}s"></i>'
                   for h, d in [(18, .1), (34, .5), (52, .2), (40, .7), (60, .3), (30, .9), (46, .4), (58, .6),
                                (26, .2), (42, .8), (54, .1), (32, .5), (48, .3), (22, .7), (38, .4)])
    w.screen("4-dictee.html", title="Dictée", body=f"""<div class="rec">
<div class="head"><span class="pill g">{icon("arrow", 16, 2.4)}{TARGET}{m(2, "good")}</span></div>
<div class="live">Euh, ajoute un, un export CSV des… des dossiers validés dans le back-office, euh, <span class="vol">filtrable par date de</span>{m(1)}</div>
<div class="wave">{bars}</div>
<div class="time">0:07</div>
<div class="acts">
<a class="cancel g" href="3-cible.html">{icon("x", 26)}</a>
<a class="stop" href="{next_href}"><span></span></a>{m(3, "good")}
</div>
</div>""", notes=[
        ("info", "Transcription sur l'appareil",
         "SpeechAnalyzer écrit en direct ; les mots encore provisoires restent en gris jusqu'à confirmation."),
        ("good", "La cible reste rappelée",
         "Le nom du workspace est visible pendant toute la dictée."),
        ("good", "Arrêter est une grosse cible",
         "Bouton de 112 pt au centre, atteignable sans regarder."),
    ])


def screen_cleanup(w, next_href):
    w.screen("5-nettoyage.html", title="Nettoyage", body=f"""<div class="rec">
<div class="glow"></div>
<div class="head"><span class="pill g">{icon("arrow", 16, 2.4)}{TARGET}</span></div>
<div class="live"><del>Euh, </del>ajoute un, <del>un </del>export CSV <del>des… </del>des dossiers validés dans le back-office, <del>euh, </del>filtrable par date de validation{m(1)}</div>
<a class="shimmer g" href="{next_href}">{icon("spark", 22)}<span class="t">Nettoyage…</span>{m(2, "weak")}</a>
<div class="fm">Foundation Models, sur l'appareil</div>
</div>""", notes=[
        ("info", "Ce qui est retiré se voit",
         "Hésitations, répétitions et faux départs sont barrés ; rien n'est ajouté ni reformulé."),
        ("weak", "Une attente de plus",
         "Une à deux secondes. Si Apple Intelligence est coupé, l'étape est sautée et l'aperçu le signale (écran hors parcours)."),
    ])


def preview_body(*, target, text, source, send_href, marks=None, warn_block="", send_on=True, keyboard=False):
    marks = marks or {}
    status = status_of(target)
    busy = ""
    if status in ("working", "blocked"):
        busy = (f'<div class="pv-busy">{icon("clock", 16, 2.2)}Occupé : l\'envoi partira dès qu\'il aura fini.'
                f'{marks.get("busy", "")}</div>')
    text_html = text if text else '<span class="caret"></span><span class="ph">Que doit faire l\'agent ?</span>'
    send_cls = "big-btn pv-send tint" + ("" if send_on else " off")
    bottom = "" if keyboard else f"""<div class="pv-spacer"></div>
<a class="{send_cls}" href="{send_href}">{icon("up", 24, 2.6)}Envoyer{marks.get("send", "")}</a>"""
    kb = keyboard_html() if keyboard else ""
    send_top = (f'<a class="pill tint" href="{send_href}" style="padding:10px 16px{"" if send_on else ";opacity:.45"}">'
                f'Envoyer{marks.get("send", "")}</a>') if keyboard else '<span style="width:44px"></span>'
    return f"""<div class="pv">
<div class="pv-nav"><a class="round g" href="3-cible.html">{icon("x", 22)}</a><h2>Aperçu</h2>{send_top}</div>
<a class="pv-tgt g" href="changer-cible.html"><span class="arrow">{icon("arrow", 22, 2.6)}</span><span class="lbl">{target}</span><span class="st">{dot(status)}{STATUS_FR[status]}</span>{icon("chev", 20, 2.4)}{marks.get("target", "")}</a>
{busy}
<div class="pv-text g">{text_html}{marks.get("text", "")}</div>
<div class="pv-src">{source}</div>
{warn_block}
{bottom}
</div>{kb}"""


def keyboard_html():
    rows = ["azertyuiop", "qsdfghjklm"]
    keys = ["".join(f'<span class="k">{c}</span>' for c in row) for row in rows]
    third = '<span class="k w">⇧</span>' + "".join(f'<span class="k">{c}</span>' for c in "wxcvbn") + '<span class="k">\'</span><span class="k w">⌫</span>'
    fourth = '<span class="k w">123</span><span class="k w">🙂</span><span class="k sp">espace</span><span class="k ret">retour</span>'
    return '<div class="kb g">' + "".join(f'<div class="r">{r}</div>' for r in keys + [third, fourth]) + "</div>"


def dictated_source(mark=""):
    return (f'<span class="chip">{icon("spark", 14)}Dictée nettoyée{mark}</span>'
            f'<a href="brut.html">Voir l\'original</a>')


def screen_preview(w, next_href):
    w.screen("6-apercu.html", title="Aperçu", offpath=[
        ("changer-cible.html", "Changer de cible"),
        ("erreur.html", "Et si le Mac est injoignable ?"),
        ("brut.html", "Et si Apple Intelligence est coupé ?"),
    ], body=preview_body(target=TARGET, text=CLEAN_TEXT, source=dictated_source(), send_href=next_href, marks={
        "target": m(1, "good"), "busy": m(2), "text": m(3, "good"), "send": m(4, "good")}), notes=[
        ("good", "La cible se change ici",
         "Toucher le bandeau ouvre la liste des workspaces sans perdre le texte."),
        ("info", "L'occupation est annoncée avant l'envoi",
         "acme_app travaille : l'envoi sera mis en file sur le Mac, jamais de <code>/clear</code> sur un agent en plein travail."),
        ("good", "Texte relu et éditable",
         "Même écran pour les trois sources : on corrige une erreur de transcription avant d'envoyer."),
        ("good", "Envoyer sous le pouce",
         "Un seul bouton pleine largeur, en bas."),
    ])


def aside_write(w):
    w.aside("ecrire.html", title="Écrire", back="3-cible.html", body=preview_body(
        target=TARGET, text="", source='<span class="chip">' + icon("pencil", 14) + "Saisie</span>",
        send_href="#", send_on=False, keyboard=True, marks={"text": m(1), "send": m(2)}), notes=[
        ("info", "Clavier ouvert d'emblée",
         "Écrire ouvre l'aperçu vide, curseur actif : on tape directement."),
        ("info", "Envoyer remonte en haut",
         "Le clavier occupe le bas ; Envoyer reste grisé tant que le texte est vide."),
    ])


def aside_paste(w):
    w.aside("coller.html", title="Coller", back="3-cible.html", body=preview_body(
        target=TARGET, text=PASTE_TEXT,
        source=f'<span class="chip">{icon("clip", 14)}Collé depuis le presse-papier{m(1, "weak")}</span>',
        send_href="6-apercu.html", marks={"text": m(2, "good")}), notes=[
        ("weak", "Alerte de collage iOS",
         "Un bouton Coller dessiné sur mesure déclenche « Autoriser le collage ? ». <code>PasteButton</code> l'évite mais impose son apparence ; sinon l'utilisateur règle « Toujours autoriser » dans Réglages."),
        ("good", "Toujours relu avant envoi",
         "Le presse-papier n'est jamais envoyé directement : il remplit l'aperçu."),
    ])


def aside_target_sheet(w):
    items = []
    for label, status, is_queued in state(frozenset()):
        cls = "it tint" if label == TARGET else "it"
        tail = icon("check", 20, 3) if label == TARGET else f'<span class="st">{STATUS_FR[status]}</span>'
        items.append(f'<a class="{cls}" href="6-apercu.html">{dot(status)}<span class="lbl">{label}</span>'
                     f'{wait_badge() if is_queued else ""}{tail}</a>')
    base = preview_body(target=TARGET, text=CLEAN_TEXT, source=dictated_source(), send_href="7-envoye.html")
    w.aside("changer-cible.html", title="Changer de cible", back="6-apercu.html", body=f"""{base}
<div class="sheet-dim"></div>
<div class="sheet g"><div class="grab"></div><h3>Envoyer vers…{m(1)}</h3>
{chr(10).join(items)}
</div>""", notes=[
        ("info", "Même liste, mêmes états",
         "Ordre herdr, ~ en premier, dots d'état et badge « en attente » identiques à l'accueil."),
    ])


def aside_error(w):
    block = f"""<div class="pv-warn err g">{icon("alert", 20, 2.2)}<div><b>Mac injoignable{m(1)}</b>LAN ({LAN_ADDR}) puis Tailscale ({TAILSCALE_ADDR}) essayés. Le texte est conservé.{m(2, "good")}</div></div>"""
    w.aside("erreur.html", title="Mac injoignable", back="6-apercu.html", body=preview_body(
        target=TARGET, text=CLEAN_TEXT, source=dictated_source(), send_href="7-envoye.html",
        warn_block=block).replace(">Envoyer<", ">Réessayer<"), notes=[
        ("info", "Les deux chemins ont été tentés",
         "Adresse LAN retenue à l'appairage, puis Tailscale. Rien n'est parti : pas de fichier de file sur le Mac."),
        ("good", "Rien n'est perdu",
         "Le texte reste dans l'aperçu ; Réessayer relance l'envoi tel quel."),
    ])


def aside_raw(w):
    block = f"""<div class="pv-warn fm g">{icon("alert", 20, 2.2)}<div><b>Transcription brute{m(1)}</b>Apple Intelligence est indisponible : hésitations conservées.</div></div>"""
    w.aside("brut.html", title="Transcription brute", back="6-apercu.html", body=preview_body(
        target=TARGET, text=RAW_TEXT + m(2, "weak"),
        source=f'<span class="chip">{icon("mic", 14)}Dictée brute</span>',
        send_href="7-envoye.html", warn_block=block), notes=[
        ("info", "Signalé dans l'aperçu",
         "Foundation Models indisponible ou modèle pas prêt : on garde la transcription brute et on le dit."),
        ("weak", "À nettoyer à la main",
         "L'agent est prévenu des erreurs de dictée par la consigne, mais les « euh » partent tels quels si on ne les retire pas."),
    ])


# ---------- Walkthrough ----------


HOME_APPS = ["Calendrier", "Photos", "Météo", "Notes", "Plans", "Réglages", None, "Musique",
             "Fichiers", "Horloge", "Rappels", "Podcasts", "Caméra", "Livres", "Santé", "Wallet"]


def aside_icon(w):
    apps = "".join(
        f'<div class="hs-app hs-me">{brand_logo("hs-ico")}<small>{brand_name()}{m(1)}</small></div>' if label is None
        else f'<div class="hs-app"><i class="hs-ico g"></i><small>{label}</small></div>'
        for label in HOME_APPS)
    w.aside("icone.html", title="Icône sur l'écran d'accueil", back="1-appairage.html",
            body=f'''<div class="hs"><div class="hs-grid">{apps}</div>
<div class="hs-dock g"><i class="hs-ico"></i><i class="hs-ico"></i><i class="hs-ico"></i><i class="hs-ico"></i></div></div>''',
            notes=[("info", "Logo et nom interchangeables",
                    "Le logo et le nom se choisissent dans l'explorer, ou par <code>?logo=4-troupeau&amp;name=Holler</code> dans l'URL. Le choix est retenu d'une page à l'autre.")])


def aside_launch(w):
    w.aside("lancement.html", title="Lancement", back="1-appairage.html",
            body=f'''<div class="launch">{brand_logo("launch-ico")}<div class="launch-name">{brand_name()}</div>
<div class="launch-sub">pour herdr</div></div>''')


def brand_script():
    return ("<script>(function(){var k='protoBrand',b={},q=new URLSearchParams(location.search);"
            "try{b=JSON.parse(localStorage.getItem(k)||'{}')}catch(e){}"
            "if(q.get('logo'))b.logo=q.get('logo');if(q.get('name'))b.name=q.get('name');"
            "try{localStorage.setItem(k,JSON.stringify(b))}catch(e){}"
            "function apply(){document.querySelectorAll('.brand-logo').forEach(function(i){"
            "if(b.logo&&/^[a-z0-9-]+$/.test(b.logo))i.src=i.getAttribute('src').replace(/[^/]+\\.svg$/,b.logo+'.svg')});"
            "document.querySelectorAll('.brand-name').forEach(function(n){if(b.name)n.textContent=b.name})}"
            "document.addEventListener('DOMContentLoaded',apply);"
            "window.addEventListener('message',function(e){if(e.data&&e.data.brand){b=e.data.brand;apply()}})})()</script>")


def view_script():
    return ("<script>(function(){var k='protoView',v=null;try{v=localStorage.getItem(k)}catch(e){}"
            "document.documentElement.dataset.view=v||'both';"
            "document.addEventListener('click',function(e){var b=e.target.closest('[data-set-view]');if(!b)return;"
            "document.documentElement.dataset.view=b.dataset.setView;try{localStorage.setItem(k,b.dataset.setView)}catch(e){}})})()</script>")


def notes_html(title, notes):
    out = [f'<div class="notes"><p class="title">{title}</p>']
    if notes:
        out.append(f'<h2>{LABELS["annotations"]}</h2>')
    for i, (kind, note_title, body) in enumerate(notes, 1):
        modifier = "" if kind == "info" else f" note--{kind}"
        out.append(f'<div class="note{modifier}"><span class="n">{i}</span>'
                   f'<div><b>{note_title}</b><p>{body}</p></div></div>')
    out.append("</div>")
    return "\n".join(out)


def page(*, title, strip, main, notes, single=False):
    css = "style.css" if single else "../style.css"
    layout = "layout layout--single" if single else "layout"
    return f"""<!DOCTYPE html>
<html lang="fr" data-view="both">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>{title}</title>
<link rel="stylesheet" href="{css}">
{view_script()}
{brand_script()}
</head>
<body>
{strip}
<div class="{layout}">
<div class="main">
{main}
</div>
{notes}
</div>
<footer><div class="in">{FOOTER}</div></footer>
</body>
</html>
"""


MARKER_PATTERN = re.compile(r'class="marker(?: marker--(good|weak))?">(\d+)<')


def check_markers(where, body, notes):
    seen = set()
    for kind, number in MARKER_PATTERN.findall(body):
        kind = kind or "info"
        index = int(number)
        seen.add(index)
        if index > len(notes):
            warn(f"{where}: marker {index} has no annotation")
        elif notes[index - 1][0] != kind:
            warn(f"{where}: marker {index} is {kind}, annotation is {notes[index - 1][0]}")
    for index, (kind, _, _) in enumerate(notes, 1):
        if kind not in KINDS:
            warn(f"{where}: unknown annotation kind {kind!r}")
        if index not in seen:
            warn(f"{where}: annotation {index} has no marker")


def write_file(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    clean = "\n".join(line.rstrip() for line in text.splitlines()) + "\n"
    path.write_text(clean, encoding="utf-8")


class Walkthrough:
    def __init__(self, key):
        self.key = key
        self.option = OPTIONS[key]
        self.screens = []
        self.asides = []
        WALKTHROUGHS.append(self)

    def screen(self, name, **kwargs):
        self.screens.append((name, kwargs))

    def aside(self, name, **kwargs):
        self.asides.append((name, kwargs))

    @property
    def first(self):
        return f"{self.key}/{self.screens[0][0]}"

    def body_of(self, name):
        return next(kwargs["body"] for screen_name, kwargs in self.screens if screen_name == name)

    def write(self):
        total = len(self.screens)
        names = [name for name, _ in self.screens]
        for num, (name, kwargs) in enumerate(self.screens, 1):
            prev_name = names[num - 2] if num > 1 else None
            next_name = names[num] if num < total else None
            self._write(name, LABELS["position"].format(num=num, total=total), prev_name, next_name, **kwargs)
        for name, kwargs in self.asides:
            self._write(name, LABELS["off_path"], None, None, **kwargs)

    def _write(self, name, position, prev_name, next_name, *, title, body, notes=(), offpath=(), back=None):
        label = self.option["label"]
        if back:
            nav = f'<a href="{back}">← Retour au parcours</a>'
        else:
            prev_link = f'<a href="{prev_name}">← Précédent</a>' if prev_name else '<span class="off">← Précédent</span>'
            next_link = f'<a href="{next_name}">Suivant →</a>' if next_name else '<span class="off">Suivant →</span>'
            nav = prev_link + next_link
        strip = (f'<div class="strip"><b>{label}</b> · {self.option["title"]} · {position}'
                 '<span class="views"><button data-set-view="light">Clair</button>'
                 '<button data-set-view="dark">Sombre</button><button data-set-view="both">Les deux</button></span>'
                 f'<span class="pn">{nav}</span><a href="../index.html">{LABELS["back_to_index"]}</a></div>')
        check_markers(f"{self.key}/{name}", body, notes)
        off = ""
        if offpath:
            off = ('<div class="offpath"><b>Hors parcours :</b>'
                   + "".join(f'<a href="{h}">{text}</a>' for h, text in offpath) + "</div>")
        main = (f'<div class="stage">{phone(body, "light")}{phone(body, "dark")}</div>'
                '<p class="stage-cap">Les éléments touchables de l\'écran mènent à l\'étape suivante.</p>' + off)
        write_file(ROOT / self.key / name, page(title=f"{label} — {title}", strip=strip, main=main,
                                                notes=notes_html(title, notes)))


def walkthrough(key, main, notes):
    w = Walkthrough(key)
    screen_pairing(w, "2-accueil.html")

    marks, screen_notes = notes["accueil"]
    w.screen("2-accueil.html", title="Accueil, cible ~ par défaut", offpath=[
        ("ecrire.html", "Écrire"), ("coller.html", "Coller")],
        body=main("~", {f"row:{TARGET}": "3-cible.html", "voice": "3-cible.html",
                        "write": "ecrire.html", "paste": "coller.html"}, marks=marks),
        notes=screen_notes)

    marks, screen_notes = notes["cible"]
    w.screen("3-cible.html", title=f"Cible {TARGET} choisie", offpath=[
        ("ecrire.html", "Écrire"), ("coller.html", "Coller")],
        body=main(TARGET, {"voice": "4-dictee.html", "write": "ecrire.html", "paste": "coller.html"}, marks=marks),
        notes=screen_notes)

    screen_recording(w, "5-nettoyage.html")
    screen_cleanup(w, "6-apercu.html")
    screen_preview(w, "7-envoye.html")

    marks, screen_notes = notes["envoye"]
    w.screen("7-envoye.html", title="Envoi mis en file",
             body=main(TARGET, {"voice": "4-dictee.html", "write": "ecrire.html", "paste": "coller.html"},
                       queued=frozenset({TARGET}), toast=True, marks=marks),
             notes=screen_notes)

    aside_write(w)
    aside_paste(w)
    aside_target_sheet(w)
    aside_error(w)
    aside_raw(w)
    aside_icon(w)
    aside_launch(w)
    return w


QUEUED_NOTE = ("info", "En file, pas encore envoyé",
               "acme_app travaille : le Mac garde l'envoi et le passera, précédé de <code>/clear</code>, dès que l'agent sera idle ou done.")


def direction_a():
    return walkthrough("direction-a", main_a, {
        "accueil": ({"row:~": m(1, "good"), "list": m(2, "good"), "voice": m(3, "weak")}, [
            ("good", "~ en tête, cible par défaut",
             "Au lancement, la cible est toujours ~, première ligne, déjà remplie."),
            ("good", "Peu de sur-mesure",
             "Une <code>List</code> SwiftUI avec <code>.glassEffect()</code> sur chaque rangée : le coût le plus bas des quatre."),
            ("weak", "La voix ne domine pas assez",
             "92 pt contre 72 pt pour ses voisins : plus gros, mais le dock reste une barre d'outils et l'œil va d'abord à la liste."),
        ]),
        "cible": ({f"row:{TARGET}": m(1, "good"), "target": m(2, "good"), "list": m(3, "weak")}, [
            ("good", "Sélection forte",
             "Ligne remplie de violet, texte blanc, coche. Le violet n'est utilisé par aucun état, il ne se confond pas avec le bleu « travaille »."),
            ("good", "Cible rappelée au-dessus du dock",
             "Le pouce sur le micro, l'œil lit la cible juste au-dessus."),
            ("weak", "Look d'app réglages",
             "Rangées, titre large, dock : c'est l'iOS standard que la vision veut éviter. Et le haut de la liste sort de la zone du pouce."),
        ]),
        "envoye": ({"toast": m(1), f"row:{TARGET}": m(2, "good")}, [
            QUEUED_NOTE,
            ("good", "Badge lisible dans la ligne",
             "« en attente » s'ajoute à la ligne sans masquer le dot d'état."),
        ]),
    })


def direction_b():
    return walkthrough("direction-b", main_b, {
        "accueil": ({"voice": m(1, "good"), "carousel": m(2, "weak"), "summary": m(3)}, [
            ("good", "Le micro est l'écran",
             "224 pt au centre : le geste principal est évident sans rien lire."),
            ("weak", "Workspaces cachés",
             "Trois ou quatre pastilles sur sept tiennent à l'écran : herdr-plugin-space-agents, bloqué, est hors champ."),
            ("info", "Un résumé compense en partie",
             "« 1 bloqué · 2 travaillent · 2 terminés » signale qu'il faut aller voir, sans dire où."),
        ]),
        "cible": ({"carousel": m(1, "weak"), "target": m(2, "good"), "sides": m(3, "weak")}, [
            ("weak", "Choisir demande un balayage",
             "acme_app est la quatrième pastille : il faut faire défiler le carrousel avant de la toucher, en haut de l'écran."),
            ("good", "Cible en très gros",
             "Nom en 36 pt et état juste sous le carrousel."),
            ("weak", "L'ordre Écrire · Dicter · Coller se perd",
             "Le micro est au-dessus, pas entre les deux : Écrire et Coller ont l'air secondaires."),
        ]),
        "envoye": ({"toast": m(1), "target": m(2, "good")}, [
            QUEUED_NOTE,
            ("good", "Badge sous la cible",
             "« en attente » apparaît sous le nom et dans la pastille."),
        ]),
    })


def direction_c():
    return walkthrough("direction-c", main_c, {
        "accueil": ({"row:~": m(1, "good"), "list": m(2, "good"), "row:herdr-plugin-space-agents": m(3, "weak")}, [
            ("good", "La carte est la cible",
             "La carte ~ est ouverte et entourée : impossible de rater la cible."),
            ("good", "Une couleur par workspace",
             "On reconnaît le workspace à sa couleur avant de lire son nom."),
            ("weak", "Couleurs d'identité contre couleurs d'état",
             "Une carte ocre portant un dot orange « bloqué » : les deux codes se brouillent, la palette devra éviter les teintes d'état."),
        ]),
        "cible": ({f"row:{TARGET}": m(1), "list": m(2, "weak"), "voice": m(3, "weak")}, [
            ("info", "La carte s'ouvre sur place",
             "L'ordre herdr ne bouge pas : ~ reste en haut, la carte choisie s'agrandit là où elle est."),
            ("weak", "Composant entièrement sur mesure",
             "Pile, chevauchement, ouverture animée : ni <code>List</code> ni grille, VoiceOver et Dynamic Type à refaire."),
            ("weak", "La voix domine peu",
             "Tuile de 150 × 132 contre 104 × 96 : plus haute, mais les trois tuiles se lisent comme un trio."),
        ]),
        "envoye": ({"toast": m(1), f"row:{TARGET}": m(2, "good")}, [
            QUEUED_NOTE,
            ("good", "Badge sur la carte",
             "« en attente » s'affiche dans la carte ouverte."),
        ]),
    })


def direction_d():
    return walkthrough("direction-d", main_d, {
        "accueil": ({"row:freebox-delta-vm": m(1, "good"), "read": m(2), "voice": m(3, "good")}, [
            ("good", "Tout ce qui se touche est en bas",
             "Grille et boutons tiennent dans la moitié basse de l'écran : atteignables au pouce, en marchant."),
            ("info", "Zone haute en lecture seule",
             "La cible en 40 pt, lisible de loin. Rien à toucher là où le pouce n'arrive pas."),
            ("good", "La voix comme un déclencheur photo",
             "128 pt en saillie au-dessus de la barre, entre Écrire et Coller : l'ordre de la spec est respecté et la voix domine."),
        ]),
        "cible": ({f"row:{TARGET}": m(1, "good"), "status": m(2), "row:herdr-plugin-space-agents": m(3, "weak")}, [
            ("good", "Double signal",
             "La tuile se remplit et la zone haute change de nom : on ne se trompe pas de cible."),
            ("info", "L'état de la cible est annoncé",
             "« travaille · l'envoi partira après son travail » avant même d'ouvrir l'aperçu."),
            ("weak", "Noms longs sur deux lignes",
             "En demi-largeur, herdr-plugin-space-agents se coupe. Au-delà d'une dizaine de workspaces, la grille doit défiler."),
        ]),
        "envoye": ({"toast": m(1), "status": m(2, "good")}, [
            QUEUED_NOTE,
            ("good", "Badge dans la tuile et sous la cible",
             "« en attente » apparaît aux deux endroits."),
        ]),
    })


# ---------- Index ----------


def thumbnail(w):
    body = w.body_of("3-cible.html")
    body = re.sub(r' href="[^"]*"', "", body).replace("<a ", "<span ").replace("</a>", "</span>")
    body = re.sub(r'<span class="marker[^"]*">\d+</span>', "", body)
    return (f'<a class="thumbs" href="{w.first}"><span class="thumb">{phone(body, "light")}</span>'
            f'<span class="thumb">{phone(body, "dark")}</span></a>')


def index():
    cards = []
    for w in WALKTHROUGHS:
        option = w.option
        reco = " opt--reco" if option.get("reco") else ""
        where = " · ".join(filter(None, [LABELS["screens"].format(n=len(w.screens)), option.get("where")]))
        cards.append(f"""<div class="opt{reco}">
<div class="where">{where}</div>
<h3>{option["label"]}. {option["title"]}</h3>
{thumbnail(w)}
<div class="grow">
<p><b>{LABELS["scenario"]}</b> {option["scenario"]}</p>
<p><b>{LABELS["requires"]}</b> {option["requires"]}</p>
</div>
<a class="btn" href="{w.first}">{LABELS["walk"]}</a>
</div>""")

    head = "".join(('<th class="reco">' if w.option.get("reco") else "<th>") + w.option["label"] + "</th>"
                   for w in WALKTHROUGHS)
    rows = ["<tr><th>{}</th>{}</tr>".format(
        LABELS["screens_row"], "".join(f"<td>{len(w.screens)} + {len(w.asides)} hors parcours</td>" for w in WALKTHROUGHS))]
    for criterion, cells in CRITERIA:
        tds = []
        for w in WALKTHROUGHS:
            kind, text = cells.get(w.key, ("", ""))
            tds.append(f'<td class="{kind}">{text}</td>')
        rows.append(f"<tr><th>{criterion}</th>{''.join(tds)}</tr>")

    reading = f"""<h2>{LABELS["reading"]}</h2>
<p>Chaque écran est montré en clair et en sombre côte à côte ; le sélecteur du bandeau n'en garde qu'un. Les éléments touchables du téléphone (rangée, bouton voix, Envoyer…) mènent à l'écran suivant, comme les liens Précédent et Suivant du bandeau. Les écrans hors parcours (Écrire, Coller, changer de cible, erreurs) sont liés sous le téléphone.</p>
<p>{LABELS["notes_legend"].format(info=m(1), good=m(2, "good"), weak=m(3, "weak"))}</p>
<p>Les écrans 1 et 4 à 6 et tous les écrans hors parcours sont identiques d'une direction à l'autre : seuls l'accueil (2), la sélection (3) et le retour après envoi (7) changent.</p>
<h2>{LABELS["not_shown"]}</h2>
<ul>{"".join(f"<li>{item}</li>" for item in NOT_SHOWN)}</ul>"""

    main = f"""<h1>{TITLE}</h1>
{INTRO}
{RECOMMENDATION}
<div class="opts">
{chr(10).join(cards)}
</div>
<h2>{LABELS["matrix"]}</h2>
<div class="matrix-wrap"><table class="matrix">
<thead><tr><th>{LABELS["criterion"]}</th>{head}</tr></thead>
<tbody>
{chr(10).join(rows)}
</tbody>
</table></div>
{reading}"""
    write_file(ROOT / "index.html", page(title="Compagnon herdr, directions UI", strip="", main=main, notes="", single=True))


HREF_PATTERN = re.compile(r'href="([^"#]+)"')


def copy_logos():
    target = ROOT / "logos"
    shutil.rmtree(target, ignore_errors=True)
    target.mkdir()
    for svg in LOGO_SOURCE.glob("*.svg"):
        shutil.copy(svg, target / svg.name)


def clean():
    for key in OPTIONS:
        for stale in (ROOT / key).glob("*.html"):
            stale.unlink()


def check_links():
    for html_page in ROOT.rglob("*.html"):
        for target in HREF_PATTERN.findall(html_page.read_text(encoding="utf-8")):
            if re.match(r"^[a-z]+:", target):
                continue
            if not (html_page.parent / target).resolve().exists():
                warn(f"{html_page.relative_to(ROOT)}: broken link {target}")


if __name__ == "__main__":
    clean()
    copy_logos()
    for build in (direction_a, direction_b, direction_c, direction_d):
        build().write()
    index()
    check_links()
    for message in WARNINGS:
        print(f"warning: {message}", file=sys.stderr)
    print(f"{sum(len(w.screens) + len(w.asides) for w in WALKTHROUGHS)} screens, "
          f"{len(WALKTHROUGHS)} options, {len(WARNINGS)} warnings")
