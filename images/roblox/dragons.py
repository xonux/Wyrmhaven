"""2D flat dragons (SVG fragments), Fire palette of DragonBuilder.luau.
Both face right, feet on y = 0, x = 0 at the body's middle. Shading: each
part has a base colour and a darker lower half (clipped), plus a soft dark
edge line - the faceted 'light/shade halves' look of the game's icons."""

C = dict(main="#f2823b", dark="#e0542c", shade="#c9502a", belly="#ffd892", bellyShade="#f0bb6e",
         membrane="#e85e30", membraneDark="#b8401f", flame0="#e44828", flame1="#ffc84c", claw="#ffeece",
         iris="#ffbc38", pupil="#24100c", line="#6e2410")


def part(d, fill, shade=None, cut=None, uid=""):
    """A filled path; with `shade`, its part below y = cut is drawn darker."""
    out = f'<path d="{d}" fill="{fill}" stroke="{C["line"]}" stroke-width="5" stroke-linejoin="round"/>'
    if shade is not None:
        out += (f'<clipPath id="c{uid}"><rect x="-2000" y="{cut}" width="4000" height="2000"/></clipPath>'
                f'<path d="{d}" fill="{shade}" clip-path="url(#c{uid})"/>'
                f'<path d="{d}" fill="none" stroke="{C["line"]}" stroke-width="5" stroke-linejoin="round"/>')
    return out


def flame(x, y, s, rot=0):
    """Three flame tongues (tail tip, crest)."""
    return (f'<g transform="translate({x} {y}) rotate({rot}) scale({s})">'
            f'<path d="M0 0 C-30 -30 -10 -70 -40 -110 C10 -90 30 -50 20 -20 C30 -40 45 -50 50 -75 C70 -40 60 -10 40 10 Z" '
            f'fill="{C["flame0"]}" stroke="{C["line"]}" stroke-width="4" stroke-linejoin="round"/>'
            f'<path d="M8 -6 C-8 -28 4 -52 -12 -78 C14 -62 22 -38 18 -16 Z" fill="{C["flame1"]}"/></g>')


def adult(uid="a"):
    g = []
    # far wing (behind the body), darker
    g.append(part("M10 -250 L-60 -440 L-300 -470 C-280 -430 -260 -400 -270 -370 C-230 -380 -210 -360 -210 -320 "
                  "C-170 -330 -140 -300 -150 -260 C-110 -270 -60 -250 -40 -210 Z", C["membraneDark"]))
    # tail
    g.append(part("M-110 -205 C-200 -200 -260 -120 -330 -95 C-380 -80 -410 -110 -430 -140 "
                  "C-410 -80 -375 -45 -330 -48 C-250 -55 -190 -125 -110 -135 Z", C["main"], C["shade"], -110, uid + "t"))
    g.append(flame(-428, -138, 1.1, -70))
    # back leg far
    g.append(part("M-40 -150 C-30 -90 -20 -60 -40 -20 L-30 0 L20 0 L20 -15 C10 -40 20 -90 20 -150 Z", C["shade"]))
    # body
    g.append(part("M-150 -170 C-150 -240 -60 -270 40 -265 C140 -260 180 -220 170 -160 C160 -110 90 -95 0 -95 "
                  "C-90 -95 -150 -120 -150 -170 Z", C["main"], C["shade"], -160, uid + "b"))
    g.append(part("M-110 -120 C-60 -100 60 -95 150 -125 C140 -105 90 -95 0 -95 C-60 -95 -95 -105 -110 -120 Z", C["bellyShade"]))
    # dorsal spikes
    for x, y, s in ((-90, -238, 0.55), (-20, -262, 0.65), (50, -268, 0.6)):
        g.append(flame(x, y, s, -10))
    # hind leg near
    g.append(part("M-130 -190 C-60 -200 -30 -150 -50 -110 C-60 -80 -40 -50 -20 -25 L10 -25 L20 0 L-80 0 "
                  "L-80 -15 C-90 -50 -110 -80 -130 -110 C-150 -140 -150 -180 -130 -190 Z", C["main"], C["shade"], -90, uid + "h"))
    # front legs
    g.append(part("M95 -140 C90 -90 95 -60 110 -30 L100 0 L150 0 L150 -15 C135 -40 135 -90 140 -140 Z", C["shade"]))
    g.append(part("M120 -150 C120 -100 125 -60 140 -30 L130 0 L190 0 L190 -15 C170 -40 165 -100 170 -150 Z", C["main"], C["shade"], -70, uid + "f"))
    for x in (-75, -45, -15, 135, 160, 185):  # claws
        g.append(f'<path d="M{x} 0 l8 -16 l8 16 Z" fill="{C["claw"]}" stroke="{C["line"]}" stroke-width="3"/>')
    # neck
    g.append(part("M120 -230 C150 -300 170 -350 190 -385 L250 -365 C230 -320 215 -260 175 -170 Z", C["main"], C["shade"], -280, uid + "n"))
    g.append(part("M175 -175 C205 -250 220 -310 238 -360 L250 -365 C235 -300 220 -240 185 -160 Z", C["belly"]))
    # near wing (in front of the body)
    g.append(part("M40 -240 L-20 -470 L-260 -520 C-235 -480 -220 -450 -235 -410 C-190 -420 -165 -395 -170 -350 "
                  "C-125 -360 -95 -330 -110 -280 C-60 -295 -10 -270 10 -215 Z", C["membrane"], C["membraneDark"], -330, uid + "w"))
    for tip in ((-260, -520), (-235, -410), (-170, -350), (-110, -280)):
        g.append(f'<path d="M-20 -470 L{tip[0]} {tip[1]}" stroke="{C["dark"]}" stroke-width="10" stroke-linecap="round"/>')
    g.append(f'<path d="M40 -240 L-20 -470" stroke="{C["main"]}" stroke-width="22" stroke-linecap="round"/>')
    g.append(f'<path d="M-20 -470 l-6 -34 l22 26 Z" fill="{C["claw"]}" stroke="{C["line"]}" stroke-width="3"/>')
    # head: skull + snout, jaw, horns, crest
    g.append(part("M240 -372 C270 -352 315 -350 352 -368 C340 -350 300 -338 268 -340 C250 -342 240 -355 240 -372 Z",
                  C["belly"]))  # closed jaw
    g.append(part("M180 -400 C185 -450 230 -470 270 -462 C300 -456 330 -430 360 -400 C372 -388 368 -370 350 -366 "
                  "C320 -362 290 -362 270 -360 C240 -358 205 -360 190 -375 Z", C["main"], C["shade"], -385, uid + "hd"))
    # two horns sweeping back from the top of the head
    for d in ("M205 -440 C175 -470 140 -490 92 -500 C130 -478 160 -455 180 -425 Z",
              "M240 -458 C215 -495 185 -520 140 -540 C175 -510 200 -485 215 -448 Z"):
        g.append(f'<path d="{d}" fill="{C["claw"]}" stroke="{C["line"]}" stroke-width="5" stroke-linejoin="round"/>')
    g.append(f'<path d="M255 -432 Q275 -440 300 -428" fill="none" stroke="{C["line"]}" stroke-width="7" stroke-linecap="round"/>')
    g.append(f'<ellipse cx="278" cy="-416" rx="15" ry="12" fill="{C["iris"]}" stroke="{C["line"]}" stroke-width="3"/>')
    g.append(f'<ellipse cx="281" cy="-416" rx="4" ry="9" fill="{C["pupil"]}"/>')
    g.append(f'<circle cx="276" cy="-421" r="3" fill="#fff"/>')
    g.append(f'<ellipse cx="345" cy="-392" rx="5" ry="3" fill="{C["pupil"]}"/>')
    g.append(flame(195, -380, 0.45, -60))
    return "".join(g)


def baby(uid="b"):
    g = []
    g.append(part("M-60 -120 C-120 -115 -150 -70 -190 -60 C-215 -55 -230 -75 -238 -92 C-232 -50 -210 -35 -185 -38 "
                  "C-140 -45 -110 -85 -60 -90 Z", C["main"], C["shade"], -75, uid + "t"))
    g.append(flame(-236, -94, 0.6, -70))
    g.append(part("M-20 -150 L-60 -250 L-170 -260 C-150 -235 -150 -215 -160 -195 C-130 -200 -115 -185 -120 -160 "
                  "C-90 -165 -60 -150 -50 -120 Z", C["membrane"], C["membraneDark"], -200, uid + "w"))
    g.append(part("M-95 -100 C-95 -150 -40 -165 20 -160 C80 -155 100 -125 95 -95 C90 -65 45 -55 0 -55 "
                  "C-50 -55 -95 -65 -95 -100 Z", C["main"], C["shade"], -95, uid + "b"))
    g.append(part("M-70 -70 C-30 -55 40 -55 85 -75 C75 -60 45 -55 0 -55 C-40 -55 -60 -60 -70 -70 Z", C["bellyShade"]))
    g.append(part("M-80 -100 C-40 -110 -25 -80 -35 -55 L-20 -18 L0 0 L-60 0 L-60 -12 C-70 -40 -95 -70 -80 -100 Z", C["main"], C["shade"], -50, uid + "h"))
    g.append(part("M45 -90 C45 -60 50 -35 60 -18 L55 0 L95 0 L95 -10 C85 -30 85 -60 88 -90 Z", C["main"], C["shade"], -45, uid + "f"))
    for x in (-55, -35, -15, 60, 78):
        g.append(f'<path d="M{x} 0 l6 -12 l6 12 Z" fill="{C["claw"]}" stroke="{C["line"]}" stroke-width="3"/>')
    # big round head (a baby's head is about as big as its body)
    g.append(part("M40 -150 C40 -230 90 -270 150 -268 C215 -266 250 -225 250 -185 C250 -150 230 -128 200 -122 "
                  "C160 -115 110 -118 80 -125 C55 -130 40 -138 40 -150 Z", C["main"], C["shade"], -170, uid + "hd"))
    g.append(part("M150 -140 C185 -132 220 -132 245 -150 C240 -128 215 -118 190 -118 C170 -118 155 -125 150 -140 Z", C["belly"]))
    for x, y, s, r in ((95, -258, 0.55, -40), (130, -270, 0.6, -15), (60, -235, 0.45, -70)):
        g.append(flame(x, y, s, r))
    g.append(f'<ellipse cx="170" cy="-200" rx="26" ry="28" fill="{C["iris"]}" stroke="{C["line"]}" stroke-width="4"/>')
    g.append(f'<ellipse cx="175" cy="-198" rx="9" ry="18" fill="{C["pupil"]}"/>')
    g.append(f'<circle cx="166" cy="-210" r="6" fill="#fff"/>')
    g.append(f'<path d="M140 -232 Q170 -246 200 -230" fill="none" stroke="{C["line"]}" stroke-width="7" stroke-linecap="round"/>')
    g.append(f'<ellipse cx="238" cy="-182" rx="4" ry="3" fill="{C["pupil"]}"/>')
    return "".join(g)
