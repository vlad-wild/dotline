# dotline — todoman reads the same vdir directory as khal (VTODO items
# live alongside VEVENT in the same collection, per CalDAV — vdirsyncer's
# "tasks" pair above syncs them into ~/.tasks/, kept separate from
# ~/.calendars/ so khal's own glob (~/.calendars/*) doesn't also try to
# show todos as events). Python syntax confirmed from todoman's own
# config.py.sample, not guessed.
path = "~/.tasks/*"
date_format = "%d.%m.%Y"
time_format = "%H:%M"
default_due = 24
