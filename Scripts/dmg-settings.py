# Layout of Awaker.dmg, read by dmgbuild (see Scripts/make-dmg.sh): the app on the left, the Applications
# folder on the right, and a picture with an arrow between them (Scripts/make-dmg-background.swift).
# dmgbuild writes the Finder layout itself, without scripting Finder, so it also works on a CI runner.
# `defines` is provided by dmgbuild from the -D options.
app = defines["app"]  # noqa: F821

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821  (its @2x version is picked up next to it)
# The window's content is 660 x 400 points, like the picture.
window_rect = ((240, 160), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

arrange_by = None
icon_size = 128
text_size = 13
# Centres of the icons, from the top left. The arrow of the picture sits between them.
icon_locations = {"Awaker.app": (170, 180), "Applications": (490, 180)}
